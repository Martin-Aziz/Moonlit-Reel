import SwiftUI

// MARK: - Logo View Helper

struct LogoView: View {
    @Environment(\.themeService) var themeService

    var size: CGFloat = 48
    var showShadow: Bool = true

    var body: some View {
        Group {
            if let nsImage = NSImage(named: "Logo") {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .shadow(
                        color: themeService.colors.accentColor.opacity(0.3),
                        radius: showShadow ? themeService.materials.shadowRadius : 0,
                        y: showShadow ? 2 : 0
                    )
            } else {
                // Fallback: Placeholder circle
                Circle()
                    .fill(themeService.colors.cardBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(themeService.colors.accentColor)
                    )
            }
        }
    }
}

// MARK: - Logo with Text (For Sidebar/About)

struct LogoWithText: View {
    @Environment(\.themeService) var themeService

    var body: some View {
        HStack(spacing: 12) {
            LogoView(size: 40, showShadow: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Moonlit Reel")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(themeService.colors.primary)

                Text("A beautiful media player")
                    .font(.caption)
                    .foregroundColor(themeService.colors.secondary)
            }
        }
    }
}

#Preview {
    LogoView()
        .padding()
}
