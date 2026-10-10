import Foundation

/// 联网搜到的食物。数据来自 Open Food Facts（免费、开放、无需 key）。
///
/// 现实情况：中文站点对**包装食品**覆盖还可以（有图、有条码、有营养表），
/// 家常菜几乎查不到，所以它只是本地库的补充，而不是替代。
struct RemoteFood: Identifiable, Hashable {
    /// 条码，可能为空。
    let id: String
    let name: String
    let brand: String?
    let imageURL: String?
    let kcalPer100: Double
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double

    /// 列表里的副标题：品牌 + 每 100 克热量。
    var subtitle: String {
        var parts: [String] = []
        if let brand = brand, !brand.isEmpty {
            parts.append(brand)
        }
        if kcalPer100 > 0 {
            parts.append("每 100 克 \(Int(kcalPer100.rounded())) 千卡")
        } else {
            parts.append("没有营养数据，选了自己填热量")
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

/// Open Food Facts 客户端。
///
/// 实测中文站响应偏慢（秒级到十秒级都有），所以超时给得比较宽松，
/// 界面上必须先出「搜索中」，失败要能降级回本地库，不能把用户卡住。
actor FoodSearchService {
    static let shared = FoodSearchService()

    private let session: URLSession
    private let baseURL = "https://cn.openfoodfacts.org"

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 14
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func search(_ keyword: String, limit: Int = 25) async throws -> [RemoteFood] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: baseURL + "/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "fields", value: "code,product_name,brands,image_small_url,nutriments"),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("SummitScale/0.3 (iOS; personal calorie log)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }
            guard (200..<300).contains(http.statusCode) else {
                throw FoodSearchError.badResponse(http.statusCode)
            }
            return Self.decode(data)
        } catch let error as FoodSearchError {
            throw error
        } catch {
            throw FoodSearchError.offline
        }
    }

    // MARK: - 解析

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
                fatPer100: number(nutriments["fat_100g"])
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
