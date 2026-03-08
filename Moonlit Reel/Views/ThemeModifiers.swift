import SwiftUI

// MARK: - Theme Modifiers

extension View {
    /// Apply the current theme's background gradient to a view
    func themeBackground() -> some View {
        modifier(ThemeBackgroundModifier())
    }

    /// Apply theme styling to card-style containers (albums, items, etc.)
    func themeCard() -> some View {
        modifier(ThemeCardModifier())
    }

    /// Apply theme text styling with specific style
    func themeText(style: TextStyle = .body) -> some View {
        modifier(ThemeTextModifier(style: style))
    }

    /// Apply theme styling to primary buttons
    func themePrimaryButton() -> some View {
        modifier(ThemePrimaryButtonModifier())
    }

    /// Apply theme styling to secondary buttons
    func themeSecondaryButton() -> some View {
        modifier(ThemeSecondaryButtonModifier())
    }

    /// Apply theme foreground color
    func themeForeground(style: TextStyle = .body) -> some View {
        modifier(ThemeForegroundModifier(style: style))
    }

    /// Apply theme divider styling
    func themeDivider() -> some View {
        modifier(ThemeDividerModifier())
    }
}

// MARK: - Text Style Enumeration

enum TextStyle {
    case title
    case headline
    case body
    case caption
    case mono
}

// MARK: - Background Modifier

struct ThemeBackgroundModifier: ViewModifier {
    @Environment(\.themeService) var themeService

    func body(content: Content) -> some View {
        content
            .background(themeService.gradients.backgroundGradient)
            .ignoresSafeArea()
    }
}

// MARK: - Card Modifier

struct ThemeCardModifier: ViewModifier {
    @Environment(\.themeService) var themeService

    func body(content: Content) -> some View {
        content
            .background(themeService.colors.cardBackground)
            .cornerRadius(themeService.materials.cornerRadius)
            .shadow(
                color: themeService.materials.shadowColor.opacity(themeService.materials.shadowOpacity),
                radius: themeService.materials.shadowRadius,
                y: 2
            )
    }
}

// MARK: - Text Modifier

struct ThemeTextModifier: ViewModifier {
    @Environment(\.themeService) var themeService
    let style: TextStyle

    func body(content: Content) -> some View {
        let font = fontForStyle(style)
        let color = colorForStyle(style)

        return content
            .font(font)
            .foregroundColor(color)
    }

    private func fontForStyle(_ style: TextStyle) -> Font {
        switch style {
        case .title:
            return themeService.typography.titleFont
        case .headline:
            return themeService.typography.headlineFont
        case .body:
            return themeService.typography.bodyFont
        case .caption:
            return themeService.typography.captionFont
        case .mono:
            return themeService.typography.monoFont
        }
    }

    private func colorForStyle(_ style: TextStyle) -> Color {
        switch style {
        case .title, .headline:
            return themeService.colors.primary
        case .body:
            return themeService.colors.primary
        case .caption:
            return themeService.colors.secondary
        case .mono:
            return themeService.colors.tertiary
        }
    }
}

// MARK: - Primary Button Modifier

struct ThemePrimaryButtonModifier: ViewModifier {
    @Environment(\.themeService) var themeService

    func body(content: Content) -> some View {
        content
            .foregroundColor(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(themeService.colors.accentColor)
            .cornerRadius(themeService.materials.cornerRadius)
    }
}

// MARK: - Secondary Button Modifier

struct ThemeSecondaryButtonModifier: ViewModifier {
    @Environment(\.themeService) var themeService

    func body(content: Content) -> some View {
        content
            .foregroundColor(themeService.colors.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(themeService.colors.cardBackground)
            .cornerRadius(themeService.materials.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: themeService.materials.cornerRadius)
                    .stroke(themeService.colors.accentColor, lineWidth: 1)
            )
    }
}

// MARK: - Foreground Modifier

struct ThemeForegroundModifier: ViewModifier {
    @Environment(\.themeService) var themeService
    let style: TextStyle

    func body(content: Content) -> some View {
        let color: Color
        switch style {
        case .title, .headline:
            color = themeService.colors.primary
        case .body:
            color = themeService.colors.primary
        case .caption:
            color = themeService.colors.secondary
        case .mono:
            color = themeService.colors.tertiary
        }

        return content
            .foregroundColor(color)
    }
}

// MARK: - Divider Modifier

struct ThemeDividerModifier: ViewModifier {
    @Environment(\.themeService) var themeService

    func body(content: Content) -> some View {
        content
            .foregroundColor(themeService.colors.dividerColor)
    }
}

// MARK: - Styled Container Views

/// A container view that applies theme card styling
struct ThemedContainer<Content: View>: View {
    @Environment(\.themeService) var themeService
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .themeCard()
    }
}

/// A themed text field background
struct ThemedTextFieldBackground: View {
    @Environment(\.themeService) var themeService

    var body: some View {
        RoundedRectangle(cornerRadius: themeService.materials.cornerRadius)
            .fill(themeService.colors.secondaryBackground)
    }
}
