import SwiftUI

// MARK: - Theme Color Structure
struct ThemeColors {
    let primary: Color           // Primary text
    let secondary: Color         // Secondary text
    let tertiary: Color          // Tertiary text
    let accentColor: Color       // Buttons, highlights, tint
    let backgroundColor: Color   // Main background
    let secondaryBackground: Color
    let groupedBackground: Color // Sidebar, grouped sections
    let cardBackground: Color    // Album cards, item containers
    let dividerColor: Color
    let successColor: Color
    let warningColor: Color
    let errorColor: Color
}

// MARK: - Theme Gradient Structure
struct ThemeGradients {
    let backgroundGradient: LinearGradient      // Full-screen gradient
    let cardGradient: LinearGradient            // Album art frame
    let miniPlayerGradient: LinearGradient      // Bottom player bar
    let fullPlayerBackground: LinearGradient    // Fullscreen player backdrop
    let visualizerBaseGradient: LinearGradient  // Fallback visualizer gradient
}

// MARK: - Theme Animation Structure
struct ThemeAnimations {
    let transitionDuration: Double              // Theme switch animation duration
    let barAnimationDuration: Double            // Visualizer bar animation duration
    let ambientAnimationDuration: Double        // Ambient effect animation duration
}

// MARK: - Theme Material Structure
struct ThemeMaterials {
    let glassMorphismOpacity: Double            // For blur effects (0-1)
    let cardBlurRadius: CGFloat
    let cornerRadius: CGFloat                   // Card corners (8-16)
    let shadowColor: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat
}

// MARK: - Theme Typography
struct ThemeTypography {
    let titleFont: Font
    let headlineFont: Font
    let bodyFont: Font
    let captionFont: Font
    let monoFont: Font = .system(.body, design: .monospaced)
}

// MARK: - Main Theme Enum
enum Theme: String, CaseIterable, Identifiable {
    case roseNight = "Rose Night"
    case cozyLatte = "Cozy Latte"
    case dreamySakura = "Dreamy Sakura"
    case moonlightVinyl = "Moonlight Vinyl"

    var id: String { rawValue }

    var isDark: Bool {
        switch self {
        case .roseNight, .moonlightVinyl: return true
        case .cozyLatte, .dreamySakura:   return false
        }
    }

    var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    // MARK: - Theme Properties

    var colors: ThemeColors {
        switch self {
        case .roseNight:
            return ThemeColors(
                primary: Color(red: 0.98, green: 0.95, blue: 0.96),
                secondary: Color(red: 0.85, green: 0.75, blue: 0.82),
                tertiary: Color(red: 0.64, green: 0.50, blue: 0.60),
                accentColor: Color(red: 0.84, green: 0.23, blue: 0.36),
                backgroundColor: Color(red: 0.10, green: 0.06, blue: 0.11),
                secondaryBackground: Color(red: 0.18, green: 0.10, blue: 0.20),
                groupedBackground: Color(red: 0.15, green: 0.08, blue: 0.17),
                cardBackground: Color(red: 0.22, green: 0.12, blue: 0.24),
                dividerColor: Color(red: 0.84, green: 0.23, blue: 0.36).opacity(0.3),
                successColor: Color(red: 0.60, green: 0.80, blue: 0.50),
                warningColor: Color(red: 0.95, green: 0.60, blue: 0.30),
                errorColor: Color(red: 0.90, green: 0.35, blue: 0.40)
            )

        case .cozyLatte:
            return ThemeColors(
                primary: Color(red: 0.29, green: 0.21, blue: 0.16),
                secondary: Color(red: 0.50, green: 0.40, blue: 0.32),
                tertiary: Color(red: 0.70, green: 0.60, blue: 0.50),
                accentColor: Color(red: 0.76, green: 0.54, blue: 0.29),
                backgroundColor: Color(red: 0.96, green: 0.94, blue: 0.93),
                secondaryBackground: Color(red: 0.92, green: 0.88, blue: 0.84),
                groupedBackground: Color(red: 0.89, green: 0.85, blue: 0.81),
                cardBackground: Color(red: 1.00, green: 0.98, blue: 0.95),
                dividerColor: Color(red: 0.76, green: 0.54, blue: 0.29).opacity(0.2),
                successColor: Color(red: 0.55, green: 0.75, blue: 0.45),
                warningColor: Color(red: 0.88, green: 0.55, blue: 0.25),
                errorColor: Color(red: 0.85, green: 0.40, blue: 0.35)
            )

        case .dreamySakura:
            return ThemeColors(
                primary: Color(red: 0.42, green: 0.30, blue: 0.48),
                secondary: Color(red: 0.60, green: 0.45, blue: 0.65),
                tertiary: Color(red: 0.78, green: 0.65, blue: 0.80),
                accentColor: Color(red: 0.91, green: 0.62, blue: 0.77),
                backgroundColor: Color(red: 0.99, green: 0.97, blue: 0.96),
                secondaryBackground: Color(red: 0.98, green: 0.94, blue: 0.98),
                groupedBackground: Color(red: 0.97, green: 0.93, blue: 0.97),
                cardBackground: Color(red: 1.00, green: 0.99, blue: 0.99),
                dividerColor: Color(red: 0.91, green: 0.62, blue: 0.77).opacity(0.15),
                successColor: Color(red: 0.65, green: 0.80, blue: 0.55),
                warningColor: Color(red: 0.92, green: 0.65, blue: 0.40),
                errorColor: Color(red: 0.88, green: 0.50, blue: 0.50)
            )

        case .moonlightVinyl:
            return ThemeColors(
                primary: Color(red: 0.88, green: 0.90, blue: 1.00),
                secondary: Color(red: 0.70, green: 0.75, blue: 0.95),
                tertiary: Color(red: 0.55, green: 0.60, blue: 0.80),
                accentColor: Color(red: 0.44, green: 0.64, blue: 0.82),
                backgroundColor: Color(red: 0.06, green: 0.10, blue: 0.16),
                secondaryBackground: Color(red: 0.12, green: 0.16, blue: 0.25),
                groupedBackground: Color(red: 0.10, green: 0.14, blue: 0.22),
                cardBackground: Color(red: 0.15, green: 0.22, blue: 0.32),
                dividerColor: Color(red: 0.44, green: 0.64, blue: 0.82).opacity(0.25),
                successColor: Color(red: 0.50, green: 0.85, blue: 0.65),
                warningColor: Color(red: 0.95, green: 0.68, blue: 0.35),
                errorColor: Color(red: 0.92, green: 0.45, blue: 0.50)
            )
        }
    }

    var gradients: ThemeGradients {
        switch self {
        case .roseNight:
            return ThemeGradients(
                backgroundGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.06, blue: 0.11),
                        Color(red: 0.25, green: 0.08, blue: 0.18)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.84, green: 0.23, blue: 0.36).opacity(0.1),
                        Color(red: 1.00, green: 0.62, blue: 0.19).opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                miniPlayerGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.18, green: 0.10, blue: 0.20),
                        Color(red: 0.25, green: 0.12, blue: 0.22)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                fullPlayerBackground: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.06, blue: 0.11),
                        Color(red: 0.20, green: 0.08, blue: 0.16),
                        Color(red: 0.30, green: 0.10, blue: 0.20)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                visualizerBaseGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.84, green: 0.23, blue: 0.36),
                        Color(red: 1.00, green: 0.62, blue: 0.19)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

        case .cozyLatte:
            return ThemeGradients(
                backgroundGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.96, green: 0.94, blue: 0.93),
                        Color(red: 0.92, green: 0.88, blue: 0.82)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.76, green: 0.54, blue: 0.29).opacity(0.08),
                        Color(red: 1.00, green: 0.80, blue: 0.55).opacity(0.04)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                miniPlayerGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.92, green: 0.88, blue: 0.84),
                        Color(red: 0.94, green: 0.90, blue: 0.86)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                fullPlayerBackground: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.96, green: 0.94, blue: 0.93),
                        Color(red: 0.94, green: 0.90, blue: 0.86),
                        Color(red: 0.92, green: 0.88, blue: 0.82)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                visualizerBaseGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.76, green: 0.54, blue: 0.29),
                        Color(red: 0.82, green: 0.50, blue: 0.20)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

        case .dreamySakura:
            return ThemeGradients(
                backgroundGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.96),
                        Color(red: 0.97, green: 0.93, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.91, green: 0.62, blue: 0.77).opacity(0.06),
                        Color(red: 0.95, green: 0.80, blue: 1.00).opacity(0.03)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                miniPlayerGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.98, green: 0.94, blue: 0.98),
                        Color(red: 0.99, green: 0.96, blue: 0.99)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                fullPlayerBackground: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.96),
                        Color(red: 0.98, green: 0.94, blue: 0.98),
                        Color(red: 0.97, green: 0.93, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                visualizerBaseGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.91, green: 0.62, blue: 0.77),
                        Color(red: 0.95, green: 0.80, blue: 1.00)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

        case .moonlightVinyl:
            return ThemeGradients(
                backgroundGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.06, green: 0.10, blue: 0.16),
                        Color(red: 0.12, green: 0.14, blue: 0.22)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.44, green: 0.64, blue: 0.82).opacity(0.1),
                        Color(red: 0.20, green: 0.40, blue: 0.70).opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                miniPlayerGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.12, green: 0.16, blue: 0.25),
                        Color(red: 0.15, green: 0.18, blue: 0.28)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                fullPlayerBackground: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.06, green: 0.10, blue: 0.16),
                        Color(red: 0.10, green: 0.12, blue: 0.20),
                        Color(red: 0.12, green: 0.14, blue: 0.22)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                visualizerBaseGradient: LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.20, green: 0.40, blue: 0.70),
                        Color(red: 0.44, green: 0.64, blue: 0.82)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    var animations: ThemeAnimations {
        switch self {
        case .roseNight:
            return ThemeAnimations(
                transitionDuration: 0.6,
                barAnimationDuration: 0.1,
                ambientAnimationDuration: 3.0
            )
        case .cozyLatte:
            return ThemeAnimations(
                transitionDuration: 0.4,
                barAnimationDuration: 0.12,
                ambientAnimationDuration: 4.0
            )
        case .dreamySakura:
            return ThemeAnimations(
                transitionDuration: 0.5,
                barAnimationDuration: 0.08,
                ambientAnimationDuration: 5.0
            )
        case .moonlightVinyl:
            return ThemeAnimations(
                transitionDuration: 0.7,
                barAnimationDuration: 0.15,
                ambientAnimationDuration: 30.0
            )
        }
    }

    var materials: ThemeMaterials {
        switch self {
        case .roseNight:
            return ThemeMaterials(
                glassMorphismOpacity: 0.8,
                cardBlurRadius: 12,
                cornerRadius: 10,
                shadowColor: Color(red: 0.84, green: 0.23, blue: 0.36),
                shadowOpacity: 0.3,
                shadowRadius: 8
            )
        case .cozyLatte:
            return ThemeMaterials(
                glassMorphismOpacity: 0.6,
                cardBlurRadius: 8,
                cornerRadius: 12,
                shadowColor: Color(red: 0.76, green: 0.54, blue: 0.29),
                shadowOpacity: 0.15,
                shadowRadius: 6
            )
        case .dreamySakura:
            return ThemeMaterials(
                glassMorphismOpacity: 0.5,
                cardBlurRadius: 6,
                cornerRadius: 16,
                shadowColor: Color(red: 0.91, green: 0.62, blue: 0.77),
                shadowOpacity: 0.1,
                shadowRadius: 4
            )
        case .moonlightVinyl:
            return ThemeMaterials(
                glassMorphismOpacity: 0.7,
                cardBlurRadius: 10,
                cornerRadius: 8,
                shadowColor: Color(red: 0.44, green: 0.64, blue: 0.82),
                shadowOpacity: 0.2,
                shadowRadius: 6
            )
        }
    }

    var typography: ThemeTypography {
        ThemeTypography(
            titleFont: .system(size: 28, weight: .bold, design: .default),
            headlineFont: .system(size: 18, weight: .semibold, design: .default),
            bodyFont: .system(size: 14, weight: .regular, design: .default),
            captionFont: .system(size: 12, weight: .regular, design: .default)
        )
    }

    var visualizerColors: [Color] {
        switch self {
        case .roseNight:
            return [
                Color(red: 0.84, green: 0.23, blue: 0.36),
                Color(red: 0.95, green: 0.40, blue: 0.30),
                Color(red: 1.00, green: 0.62, blue: 0.19),
                Color(red: 1.00, green: 0.75, blue: 0.40),
                Color(red: 0.95, green: 0.50, blue: 0.50)
            ]

        case .cozyLatte:
            return [
                Color(red: 0.76, green: 0.54, blue: 0.29),
                Color(red: 0.82, green: 0.50, blue: 0.20),
                Color(red: 0.60, green: 0.40, blue: 0.25),
                Color(red: 0.70, green: 0.55, blue: 0.35)
            ]

        case .dreamySakura:
            return [
                Color(red: 1.00, green: 0.70, blue: 0.90),
                Color(red: 0.95, green: 0.80, blue: 1.00),
                Color(red: 1.00, green: 0.85, blue: 0.95),
                Color(red: 0.85, green: 0.70, blue: 0.90)
            ]

        case .moonlightVinyl:
            return [
                Color(red: 0.20, green: 0.40, blue: 0.70),
                Color(red: 0.35, green: 0.55, blue: 0.85),
                Color(red: 0.60, green: 0.70, blue: 1.00),
                Color(red: 0.40, green: 0.80, blue: 1.00),
                Color(red: 0.44, green: 0.64, blue: 0.82)
            ]
        }
    }
}
