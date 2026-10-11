import Foundation

/// 联网搜到的食物。
struct RemoteFood: Identifiable, Hashable {
    /// 唯一键：下厨房是菜谱 ID，Open Food Facts 是条码。
    let id: String
    let name: String
    /// 来源名，列表里当副标题前缀用，比如「下厨房」。
    let brand: String?
    let imageURL: String?
    let kcalPer100: Double
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double
    /// 营养值是照着本地库哪一条估出来的；自带营养表的条目为 nil。
    let matchedLocal: String?

    /// 列表里的副标题：来源 + 每 100 克热量。
    var subtitle: String {
        var parts: [String] = []
        if let brand = brand, !brand.isEmpty {
            parts.append(brand)
        }
        if kcalPer100 > 0 {
            parts.append("每 100 克 \(Int(kcalPer100.rounded())) 千卡")
            if let matched = matchedLocal {
                // 说清楚是估的，别让人以为是菜谱作者给的精确值。
                parts.append("按本地「\(matched)」估")
            }
        } else {
            // 本地库也没对上，选完会提示自己填。
            parts.append("没有营养表，选完自己填")
        }
        return parts.joined(separator: " · ")
    }

    /// 有没有可用的热量数据。
    var hasNutrition: Bool {
        kcalPer100 > 0
    }
}

enum FoodSearchError: LocalizedError {
    case badResponse(Int)
    case offline

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "食物服务器返回了 \(code)，等会儿再试"
        case .offline:
            return "网断了，先用手动输入或本地食物库"
        }
    }
}

/// 联网食物搜索。
///
/// 主源是「下厨房」：国内直连、实测 0.5 秒左右返回、每条都带真实照片，
/// 中文家常菜覆盖比 Open Food Facts 好得多。
/// 它的短板是菜谱页不提供营养表，所以热量留空，
/// 由记一笔页面拿本地库同名条目兜底，兜不到就让用户自己填。
///
/// 备源保留 Open Food Facts 中国站：包装食品有营养表，
/// 但实测经常整站 503（多次复现），只当补充，不再作为唯一来源。
actor FoodSearchService {
    static let shared = FoodSearchService()

    private let session: URLSession
    private let xiachufang = "https://www.xiachufang.com/search/"
    /// 中国站实测长期 503（多轮复现），先试它是因为它中文条目多；挂了转世界站。
    private let openFoodFactsCN = "https://cn.openfoodfacts.org/cgi/search.pl"
    private let openFoodFactsWorld = "https://world.openfoodfacts.org/cgi/search.pl"

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// 两个源并行跑：下厨房快、Open Food Facts 慢还常挂，谁先回来都不该被另一个拖住。
    /// 两边都失败才抛错；只要有一边出结果，就正常返回。
    /// 一次多取一些，两个源各自都取这么多再合并去重，最后还会截回 limit。
    /// 早先只取 25 条，下厨房一页就吃满了，用户反馈「东西太少」。
    func search(_ keyword: String, limit: Int = 50) async throws -> [RemoteFood] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        async let local = searchXiachufang(trimmed, limit: limit)
        async let remote = searchOpenFoodFacts(trimmed, limit: limit)

        let (localResult, remoteResult) = await (try? local, try? remote)

        var merged: [RemoteFood] = []
        var seen = Set<String>()
        for food in (localResult ?? []) + (remoteResult ?? []) {
            let key = food.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            // 下厨房只给菜名和图，这里就地拿本地库的数值补上，
            // 否则列表里是一整排「0 千卡」，用户根本没法挑。
            merged.append(Self.enrich(food))
        }

        if merged.isEmpty, localResult == nil, remoteResult == nil {
            throw FoodSearchError.offline
        }

        // 补到营养的排前面。下厨房一大半条目对不上本地库，混着放要翻很久。
        let known = merged.filter { $0.hasNutrition }
        let unknown = merged.filter { !$0.hasNutrition }
        return Array((known + unknown).prefix(limit))
    }

    /// 给联网条目补营养值。
    ///
    /// 以前是等用户选中之后，在 `PickedFood(remote:)` 里才拿本地库兜底，
    /// 于是搜索结果列表上仍然是一排 0，看着就像功能坏了。
    /// 挪到这里，列表直接能看出热量；补不到才留空，由记一笔页面提示自己填。
    nonisolated static func enrich(_ food: RemoteFood) -> RemoteFood {
        guard !food.hasNutrition else { return food }
        guard let local = FoodLibrary.bestMatch(food.name) else { return food }

        return RemoteFood(
            id: food.id,
            name: food.name,
            brand: food.brand,
            imageURL: food.imageURL,
            kcalPer100: local.kcalPer100g,
            proteinPer100: local.proteinPer100g,
            carbsPer100: local.carbsPer100g,
            fatPer100: local.fatPer100g,
            matchedLocal: local.name
        )
    }

    // MARK: - 下厨房

    private func searchXiachufang(_ keyword: String, limit: Int) async throws -> [RemoteFood] {
        var components = URLComponents(string: xiachufang)
        components?.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        // 移动端 UA 拿到的页面更轻、结构更稳。
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FoodSearchError.offline
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FoodSearchError.badResponse(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.decodeXiachufang(html, limit: limit)
    }

    /// 解析下厨房搜索结果页。
    ///
    /// 卡片长这样（实测结构，注意 `src` 是占位 base64，真图在 `data-src`）：
    ///
    ///     <div class="recipe recipe-215-horizontal ...">
    ///       <a href="/recipe/107356708/">
    ///         <div class="cover"><img src="data:image/png;base64,..."
    ///              data-src="https://i2.chuimg.com/xxx.jpg?imageView2/1/w/215/h/136/..." /></div>
    ///       </a>
    ///       <div class="info"><p class="name"><a href="/recipe/107356708/">烤牛奶</a></p></div>
    ///     </div>
    ///
    /// 所以一条正则从「菜谱 ID → 真图 → 名字」一次抓全，避免按出现顺序硬配对把图和名错位。
    nonisolated static func decodeXiachufang(_ html: String, limit: Int) -> [RemoteFood] {
        guard !html.isEmpty else { return [] }

        let pattern = #"<div class="recipe[^"]*"[\s\S]*?href="/recipe/(\d+)/"[\s\S]*?data-src="([^"]+)"[\s\S]*?<p class="name">\s*<a[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        var result: [RemoteFood] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let recipeID = ns.substring(with: match.range(at: 1))
            let rawImage = ns.substring(with: match.range(at: 2))
            let rawName = ns.substring(with: match.range(at: 3))

            let name = Self.clean(rawName)
            guard !name.isEmpty, !recipeID.isEmpty else { continue }
            guard !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())

            result.append(
                RemoteFood(
                    id: "xcf-\(recipeID)",
                    name: name,
                    brand: "下厨房",
                    imageURL: Self.largerImage(rawImage),
                    // 下厨房不给营养表，留空让上层兜底或让用户自己填。
                    kcalPer100: 0,
                    proteinPer100: 0,
                    carbsPer100: 0,
                    fatPer100: 0,
                    matchedLocal: nil
                )
            )
            if result.count >= limit { break }
        }
        return result
    }

    /// 去掉标签残留和多余空白。
    private nonisolated static func clean(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 列表里 215×136 的缩略图糊得没法看，把七牛裁剪参数换大一点。
    nonisolated static func largerImage(_ url: String) -> String {
        guard url.contains("imageView2") else { return url }
        var out = url
        for size in ["/w/215/h/136", "/w/280/h/210", "/w/180/h/180"] {
            out = out.replacingOccurrences(of: size, with: "/w/320/h/320")
        }
        return out
    }

    // MARK: - Open Food Facts（备源）

    private func searchOpenFoodFacts(_ keyword: String, limit: Int) async throws -> [RemoteFood] {
        var lastError: Error?
        for base in [openFoodFactsCN, openFoodFactsWorld] {
            do {
                return try await searchOpenFoodFacts(keyword, base: base, limit: limit)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FoodSearchError.offline
    }

    private func searchOpenFoodFacts(_ keyword: String, base: String, limit: Int) async throws -> [RemoteFood] {
        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: keyword),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "fields", value: "code,product_name,brands,image_small_url,nutriments"),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("SummitScale/0.4 (iOS; personal calorie log)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FoodSearchError.offline
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FoodSearchError.badResponse(http.statusCode)
        }
        return Self.decode(data)
    }

    // MARK: - 解析（Open Food Facts）

    nonisolated static func decode(_ data: Data) -> [RemoteFood] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = root["products"] as? [[String: Any]]
        else {
            return []
        }

        var seen = Set<String>()
        var result: [RemoteFood] = []

        for product in products {
            guard let name = (product["product_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else { continue }

            let code = (product["code"] as? String) ?? ""
            let brand = (product["brands"] as? String)?.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let image = (product["image_small_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nutriments = (product["nutriments"] as? [String: Any]) ?? [:]

            let food = RemoteFood(
                id: code.isEmpty ? name : code,
                name: name,
                brand: (brand?.isEmpty ?? true) ? nil : brand,
                imageURL: (image?.isEmpty ?? true) ? nil : image,
                kcalPer100: number(nutriments["energy-kcal_100g"]),
                proteinPer100: number(nutriments["proteins_100g"]),
                carbsPer100: number(nutriments["carbohydrates_100g"]),
                fatPer100: number(nutriments["fat_100g"]),
                matchedLocal: nil
            )

            // 同一条码或同名去重，Open Food Facts 里重复条目不少。
            let key = code.isEmpty ? name : code
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(food)
        }

        // 有营养数据的排前面，省得用户点开一堆空壳。
        return result.sorted { lhs, rhs in
            if lhs.hasNutrition != rhs.hasNutrition { return lhs.hasNutrition }
            return false
        }
    }

    private nonisolated static func number(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string) { return double }
        return 0
    }
}
