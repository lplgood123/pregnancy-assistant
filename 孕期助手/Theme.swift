import SwiftUI
import UIKit

enum AppTheme {
    // Glassmorphism 背景 - 亮灰渐变（保留轻微暖感）
    static let background = LinearGradient(
        colors: [
            Color(hex: "F7F8FA"),
            Color(hex: "F1F3F6"),
            Color(hex: "E9EDF2")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 主色调 - 温柔的玫瑰粉
    static let accentBrand = Color(hex: "E88B9C")
    static let actionPrimary = Color(hex: "D97B8E")
    static let onActionPrimary = Color.white
    static let accent = actionPrimary
    static let accentSoft = Color(hex: "FFE8ED")

    // Glassmorphism 卡片 - 半透明毛玻璃效果
    static let card = Color.white.opacity(0.74)
    static let cardAlt = Color(hex: "F4F6F9").opacity(0.68)
    static let surfaceMuted = Color(hex: "ECEFF4").opacity(0.58)
    static let border = Color.white.opacity(0.4)
    static let borderLight = Color.white.opacity(0.25)

    // 文字颜色
    static let textPrimary = Color(hex: "2F3742")
    static let textSecondary = Color(hex: "667085")
    static let textHint = Color(hex: "98A2B3")

    // Banner 颜色
    static let bannerSuccess = Color(hex: "7CB89D")
    static let bannerInfo = Color(hex: "8BA4D9")
    static let bannerError = Color(hex: "E88B9C")

    // 状态颜色
    static let statusSuccess = Color(hex: "7CB89D")
    static let statusSuccessSoft = Color(hex: "E8F5EF")
    static let statusError = Color(hex: "E88B9C")
    static let statusErrorSoft = Color(hex: "FFE8ED")
    static let statusInfo = Color(hex: "8BA4D9")
    static let statusInfoSoft = Color(hex: "E8EDFA")

    // 圆角和阴影
    static let cornerRadius: CGFloat = 16
    static let chipRadius: CGFloat = 10
    static let shadowSm = Color.black.opacity(0.04)
    static let shadowMd = Color.black.opacity(0.08)
    static let glassBlur: CGFloat = 20  // 毛玻璃模糊度

    // 字体
    static let titleFont = Font.custom("Avenir Next", size: 20, relativeTo: .title3).weight(.semibold)
    static let bodyFont = Font.custom("Avenir Next", size: 16, relativeTo: .body)
    static let captionFont = Font.custom("Avenir Next", size: 13, relativeTo: .footnote)
}

enum AppLayout {
    static let mainTabBarHeight: CGFloat = 44
    static let bottomDockGap: CGFloat = 8
    static let bottomActionHeight: CGFloat = 48
    static let scrollTailPadding: CGFloat = 16

    static var mainTabBarBottomSafeInset: CGFloat {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first(where: \.isKeyWindow)
        else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }

    static var tabBarBottomSafePadding: CGFloat {
        mainTabBarBottomSafeInset
    }

    // Root tab bar total occupied height, including device bottom safe inset.
    static var tabBarOccupiedHeight: CGFloat {
        mainTabBarHeight + tabBarBottomSafePadding
    }

    // Visible spacing above custom tab bar for in-page docks.
    // Do not include safe inset here, because root safeAreaInset already consumes it.
    static var tabBarVisibleHeight: CGFloat {
        mainTabBarHeight + bottomDockGap
    }

    // Dock controls rendered inside nested tab pages need explicit offset.
    // TabView-level safeAreaInset does not reliably push nested page safeAreaInset content.
    static var dockBottomInsetAboveTabBar: CGFloat {
        tabBarVisibleHeight
    }

    // Extra trailing space for scroll/list content in tab pages.
    static var tabPageScrollTailPadding: CGFloat {
        tabBarVisibleHeight + 12
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func appTapTarget(minWidth: CGFloat = 44, minHeight: CGFloat = 44) -> some View {
        frame(minWidth: minWidth, minHeight: minHeight)
    }

    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }

    // Glassmorphism 毛玻璃效果
    func glassBackground(
        tint: Color = .white,
        opacity: Double = 0.7,
        blur: CGFloat = 20
    ) -> some View {
        self
            .background(
                tint.opacity(opacity)
                    .background(.ultraThinMaterial)
            )
    }

    // Glassmorphism 卡片效果
    func glassCard(
        cornerRadius: CGFloat = 16,
        borderColor: Color = .white.opacity(0.3),
        shadowColor: Color = .black.opacity(0.08)
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 12, x: 0, y: 4)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.onActionPrimary)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                (isEnabled ? AppTheme.actionPrimary : AppTheme.textHint)
                    .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(AppTheme.surfaceMuted.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadowSm, radius: 4, x: 0, y: 2)
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(AppTheme.accentSoft.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(AppTheme.textSecondary)
            .clipShape(Capsule())
    }
}
