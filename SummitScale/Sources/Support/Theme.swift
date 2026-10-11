import SwiftUI

/// 视觉基座：颜色、圆角、间距、卡片样式集中一处，避免每个页面各写一套。
///
/// 配色原则（对齐 Apple 人机界面指南，v0.4.0 起）：
/// 1. 层次靠灰阶与系统材质，不靠色相堆叠。页面底、卡片底、分割线全部走 systemGroupedBackground 系。
/// 2. 强调色全 App 只保留一个（accent 山青），用在主按钮、进度填充、选中态；
///    其余文字一律 label / secondaryLabel，不再每张卡片挂一个彩色图标。
/// 3. 状态色与营养素色改用系统语义色，自动跟随深浅模式与「增强对比度」辅助功能。
///    旧版六个高饱和色硬编码 RGB，深色模式下既刺眼又不跟随辅助功能。
/// 4. 不用渐变、不用彩色阴影。iOS 的卡片层次靠底色差与 1px 分隔，不靠发光。
enum Theme {
    // MARK: - 强调色

    /// 全 App 唯一强调色：玫红。直接用系统 pink（浅 #FF2D55 / 深 #FF375F），
    /// 自动跟随深浅模式与「增强对比度」，比自己写死 RGB 更稳。
    static let accent = Color(uiColor: .systemPink)

    // MARK: - 状态色

    /// 达标绿：目标完成。只用于数值与图标，不做大面积填充。
    static let success = Color(uiColor: .systemGreen)
    /// 超支警示。
    static let warning = Color(uiColor: .systemRed)

    // MARK: - 营养素三色

    /// 蛋白 / 碳水 / 脂肪三色。仅用于图例圆点与进度条填充，
    /// 配套文字一律用 primaryText / secondaryText，避免彩色文字堆叠。
    static let protein = Color(uiColor: .systemPink)
    static let carbs = Color(uiColor: .systemOrange)
    static let fat = Color(uiColor: .systemBlue)

    // MARK: - 文字与分隔

    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)
    /// 进度条轨道、未完成底衬。
    static let track = Color(uiColor: .systemFill)

    // MARK: - 底色

    /// 页面与卡片底色，跟随系统深浅模式。
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: - 尺寸

    /// 圆角统一三档：卡片 16、控件 10、胶囊用 Capsule。
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 14
    /// 触摸目标下限：Apple HIG 与 WCAG 都要求 44pt。
    static let minTouch: CGFloat = 44

    // MARK: - 字体

    /// 大号数字统一用圆体 + 等宽数字，扫一眼就能比较。
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// 统一的卡片容器。
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// 卡片内的次级小节标题。
struct CardTitle: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = symbol {
                // 图标走强调色：用户明确要的，卡片靠它拿区分度。
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.primaryText)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
