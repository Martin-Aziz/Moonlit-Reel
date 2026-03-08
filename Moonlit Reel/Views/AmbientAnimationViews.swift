import SwiftUI

// MARK: - Ambient Glow View (All Themes)

/// A subtle radial glow effect that appears behind the player
struct AmbientGlowView: View {
    @Environment(\.themeService) var themeService

    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        themeService.colors.accentColor.opacity(0.3),
                        themeService.colors.accentColor.opacity(0.1),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 250
                )
            )
            .blur(radius: themeService.materials.cardBlurRadius)
            .scaleEffect(scale)
            .animation(
                Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear {
                scale = 1.2
            }
            .ignoresSafeArea()
    }
}

// MARK: - Floating Particles View (Rose Night & Cozy Latte)

/// Canvas-based floating particles for ambient effects
struct FloatingParticlesView: View {
    @Environment(\.themeService) var themeService

    @State private var animationProgress: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            // Draw floating particles
            let particleCount = 12
            for i in 0..<particleCount {
                let angle = Double(i) / Double(particleCount) * .pi * 2
                let baseRadius: CGFloat = 100

                // Animate position based on time and angle
                let offsetX = sin(angle + Double(animationProgress) * 2) * 40
                let offsetY = cos(angle + Double(animationProgress) * 2) * 40

                let x = size.width / 2 + cos(angle) * baseRadius + offsetX
                let y = size.height / 2 + sin(angle) * baseRadius + offsetY

                var path = Path()
                let particleSize: CGFloat = 3 + CGFloat(i % 3) * 1

                path.addEllipse(in: CGRect(x: x - particleSize / 2, y: y - particleSize / 2, width: particleSize, height: particleSize))

                let opacity = 0.3 + 0.2 * sin(Double(animationProgress) * 3.5 + angle)
                context.fill(
                    path,
                    with: .color(themeService.colors.accentColor.opacity(opacity))
                )
            }
        }
        .onAppear {
            withAnimation(
                Animation.linear(duration: 20).repeatForever(autoreverses: false)
            ) {
                animationProgress = 1.0
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Blossom Petals View (Dreamy Sakura)

/// Falling sakura petals for the Dreamy Sakura theme
struct BlossomPetalsView: View {
    @Environment(\.themeService) var themeService

    var body: some View {
        Canvas { context, size in
            // Create falling petals
            let petalCount = 6
            let animationDuration = 8.0
            let currentTime = Date().timeIntervalSince1970

            for i in 0..<petalCount {
                let startDelay = Double(i) * 0.5
                let adjustedTime = currentTime + startDelay
                let petal = sin(adjustedTime / animationDuration * .pi * 2)

                let x = size.width * CGFloat(i) / CGFloat(petalCount) + sin(petal) * 40
                let y = (size.height * (CGFloat(adjustedTime.truncatingRemainder(dividingBy: animationDuration)) / animationDuration)) - size.height * 0.2

                var path = Path()
                path.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))

                let opacity = (sin(petal) + 1) / 2 * 0.5
                context.fill(
                    path,
                    with: .color(themeService.colors.accentColor.opacity(opacity))
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Vinyl Record View (Moonlight Vinyl)

/// Subtle spinning vinyl record animation
struct VinylRecordView: View {
    @Environment(\.themeService) var themeService

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer vinyl edge
            Circle()
                .stroke(
                    themeService.colors.accentColor.opacity(0.1),
                    lineWidth: 1
                )
                .frame(width: 200, height: 200)

            // Vinyl grooves effect
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            themeService.colors.accentColor.opacity(0.15),
                            themeService.colors.accentColor.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .frame(width: 180, height: 180)

            // Center label
            Circle()
                .fill(themeService.colors.secondaryBackground)
                .frame(width: 60, height: 60)

            Circle()
                .stroke(themeService.colors.accentColor.opacity(0.3), lineWidth: 1)
                .frame(width: 55, height: 55)
        }
        .rotationEffect(.degrees(rotation))
        .animation(
            Animation.linear(duration: 30).repeatForever(autoreverses: false),
            value: rotation
        )
        .onAppear {
            rotation = 360
        }
        .opacity(0.6)
    }
}

// MARK: - Breathing Glow View (Rose Night)

/// Pulsing glow effect synchronized to music intensity
struct BreathingGlowView: View {
    @Environment(\.themeService) var themeService

    let intensity: Double  // 0-1 music intensity
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Inner glow layer
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            themeService.colors.accentColor.opacity(0.4),
                            themeService.colors.accentColor.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 30,
                        endRadius: 150
                    )
                )
                .blur(radius: 30)

            // Outer glow layer
            Circle()
                .stroke(
                    themeService.colors.accentColor.opacity(0.2),
                    lineWidth: 2
                )
                .blur(radius: 10)
        }
        .scaleEffect(1.0 + CGFloat(intensity) * 0.3)
        .animation(.easeInOut(duration: 0.1), value: intensity)
        .opacity(0.5 + intensity * 0.3)
    }
}

// MARK: - Theme-Specific Ambient Container

/// Container that renders the appropriate ambient effects based on theme
struct ThemeAmbientEffects: View {
    @Environment(\.themeService) var themeService

    var body: some View {
        ZStack {
            switch themeService.currentTheme {
            case .roseNight:
                AmbientGlowView()
                FloatingParticlesView()

            case .cozyLatte:
                AmbientGlowView()
                FloatingParticlesView()

            case .dreamySakura:
                AmbientGlowView()
                BlossomPetalsView()

            case .moonlightVinyl:
                AmbientGlowView()
                VinylRecordView()
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Subtle Shimmer Effect (Optional)

/// A subtle shimmer for UI elements
struct ShimmerEffect: View {
    @State private var offset: CGFloat = -100

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.white.opacity(0.2),
                Color.clear
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: offset)
        .animation(
            Animation.linear(duration: 2).repeatForever(autoreverses: false),
            value: offset
        )
        .onAppear {
            offset = 100
        }
    }
}
