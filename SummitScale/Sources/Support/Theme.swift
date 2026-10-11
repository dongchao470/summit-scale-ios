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

    /// 全 App 唯一强调色：系统蓝（浅 #007AFF / 深 #0A84FF），
    /// 自动跟随深浅模式与「增强对比度」。用在主按钮、热量环填充、选中态。
    static let accent = Color(uiColor: .systemBlue)

    // MARK: - 状态色

    /// 达标绿：目标完成。只用于数值与图标，不做大面积填充。
    static let success = Color(uiColor: .systemGreen)
    /// 超支警示。
    static let warning = Color(uiColor: .systemRed)

    // MARK: - 营养素三色

    /// 蛋白 / 碳水 / 脂肪三色，对齐 Apple 健身三环（活动红 / 运动黄绿 / 站立青）。
    /// 按用户要求定成：蛋白青、碳水黄绿、脂肪红。各给浅/深两套 RGB——
    /// 深色下提亮到荧光，浅色下压暗以保证白底可读。仅用于进度条填充与图例圆点。
    static let protein = dynamic(light: 0x00B8C9, dark: 0x2CE0F0)
    static let carbs = dynamic(light: 0x7FBF00, dark: 0xA2F10A)
    static let fat = dynamic(light: 0xFA114F, dark: 0xFF2D55)

    /// 按浅 / 深模式取不同 16 进制色；健身环荧光色需分别调校，系统语义色无法表达。
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

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

/// 把 0xRRGGBB 整数拆成 UIColor，供健身环三色的浅/深两套硬编码使用。
private extension UIColor {
    convenience init(rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
