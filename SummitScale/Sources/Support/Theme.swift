import SwiftUI

/// 视觉基座：颜色、圆角、间距、卡片样式集中一处，避免每个页面各写一套。
///
/// 参考 ui-ux-pro-max 给健身类 App 的建议：主色能量橙（动能）、达标绿，
/// 卡片刻度统一，正文不小于 16pt，触摸目标不小于 44pt。
enum Theme {
    // MARK: - 颜色

    /// 主色：能量橙。热量环、主按钮、选中态都用它。
    static let accent = Color(red: 0.976, green: 0.451, blue: 0.086)
    /// 达标绿：运动消耗、目标完成。
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// 超支警示。
    static let warning = Color(red: 0.937, green: 0.267, blue: 0.267)

    /// 蛋白 / 碳水 / 脂肪三色。全 App 统一，图例与进度条不会打架。
    static let protein = Color(red: 0.925, green: 0.282, blue: 0.600)
    static let carbs = Color(red: 0.976, green: 0.686, blue: 0.102)
    static let fat = Color(red: 0.290, green: 0.576, blue: 0.949)

    /// 页面与卡片底色，跟随系统深浅模式。
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: - 尺寸

    static let cardRadius: CGFloat = 18
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
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
