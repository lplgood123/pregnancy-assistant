import SwiftUI
import UIKit

@main
struct PregnancyAssistantApp: App {
    @StateObject private var store = PregnancyStore()

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.card)
        appearance.shadowColor = UIColor(AppTheme.border)

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.shouldShowOnboarding {
                    OnboardingFlowView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(store)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .preferredColorScheme(.light)  // 强制浅色模式，Glassmorphism 设计
        }
    }
}
