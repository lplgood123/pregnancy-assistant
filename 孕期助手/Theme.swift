import SwiftUI
import UIKit

enum AppTheme {
    static let background = LinearGradient(
        colors: [Color(hex: "F9EFE7"), Color(hex: "F2EEE9")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let accentBrand = Color(hex: "F07A6A")
    static let actionPrimary = Color(hex: "CC4A39")
    static let onActionPrimary = Color.white
    static let accent = actionPrimary
    static let accentSoft = Color(hex: "F1E9E3")

    static let card = Color.white
    static let cardAlt = Color(hex: "F7F0EB")
    static let surfaceMuted = Color(hex: "F5F1EC")
    static let border = Color(hex: "E1D7CD")
    static let borderLight = Color(hex: "F5F1EC")

    static let textPrimary = Color(hex: "3B2F2A")
    static let textSecondary = Color(hex: "6F6056")
    static let textHint = Color(hex: "77695F")

    static let bannerSuccess = Color(hex: "4C8164")
    static let bannerInfo = Color(hex: "4D78A0")
    static let bannerError = Color(hex: "BC5555")

    static let statusSuccess = Color(hex: "3F7A58")
    static let statusSuccessSoft = Color(hex: "EDF7F1")
    static let statusError = Color(hex: "BC5555")
    static let statusErrorSoft = Color(hex: "FBEFF0")
    static let statusInfo = Color(hex: "4D78A0")
    static let statusInfoSoft = Color(hex: "EDF3F8")

    static let cornerRadius: CGFloat = 16
    static let chipRadius: CGFloat = 10
    static let shadowSm = Color.black.opacity(0.04)
    static let shadowMd = Color.black.opacity(0.08)

    static let titleFont = Font.custom("Avenir Next", size: 20, relativeTo: .title3).weight(.semibold)
    static let bodyFont = Font.custom("Avenir Next", size: 16, relativeTo: .body)
    static let captionFont = Font.custom("Avenir Next", size: 13, relativeTo: .footnote)
}

enum AppLayout {
    static let mainTabBarHeight: CGFloat = 68
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

    // Dock controls rendered inside nested tab pages need explicit offset.
    // TabView-level safeAreaInset does not reliably push nested page safeAreaInset content.
    static var dockBottomInsetAboveTabBar: CGFloat {
        tabBarOccupiedHeight + bottomDockGap
    }

    // Extra trailing space for scroll/list content in tab pages.
    static var tabPageScrollTailPadding: CGFloat {
        tabBarOccupiedHeight + 16
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
