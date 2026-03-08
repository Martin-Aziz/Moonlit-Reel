import SwiftUI

@MainActor
@Observable
final class ThemeService {
    private(set) var currentTheme: Theme = .roseNight
    private(set) var isAnimatingTransition: Bool = false

    private let persistenceKey = "theme.selected"

    init() {
        // Load persisted theme preference at launch
        if let saved = UserDefaults.standard.string(forKey: persistenceKey),
           let theme = Theme(rawValue: saved) {
            currentTheme = theme
        } else {
            // Default to Rose Night for new users
            currentTheme = .roseNight
        }
    }

    /// Set the current theme with optional smooth transition animation
    /// - Parameters:
    ///   - theme: The theme to switch to
    ///   - animated: Whether to animate the transition (default: true)
    func setTheme(_ theme: Theme, animated: Bool = true) {
        guard theme != currentTheme else { return }

        if animated {
            isAnimatingTransition = true

            withAnimation(.easeInOut(duration: theme.animations.transitionDuration)) {
                currentTheme = theme
            }

            // Mark transition as complete after animation duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64(theme.animations.transitionDuration * 1e9))
                isAnimatingTransition = false
            }
        } else {
            currentTheme = theme
        }

        // Persist selection to UserDefaults
        UserDefaults.standard.set(theme.rawValue, forKey: persistenceKey)
    }

    // MARK: - Convenience Accessors

    var colors: ThemeColors {
        currentTheme.colors
    }

    var gradients: ThemeGradients {
        currentTheme.gradients
    }

    var animations: ThemeAnimations {
        currentTheme.animations
    }

    var materials: ThemeMaterials {
        currentTheme.materials
    }

    var typography: ThemeTypography {
        currentTheme.typography
    }

    var visualizerColors: [Color] {
        currentTheme.visualizerColors
    }
}
