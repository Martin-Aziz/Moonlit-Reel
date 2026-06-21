// MiniPlayerView.swift — Persistent bottom player bar
//
// PURPOSE: Always-visible player controls at the bottom of the window.
//          Tapping the album art / title opens the full-screen player.
// LAYER:   Presentation

import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.playerService)    var playerService
    @Environment(\.audiobookService) var audiobookService
    @Environment(\.themeService)     var themeService
    @Environment(\.metadataService)  var metadataService
    @Binding var isShowingFullscreen: Bool
    @AppStorage("settings.showVisualizerInMini") private var showVisualizerInMini: Bool = true

    @State private var artwork: Image? = nil
    @State private var artworkItemID: String? = nil

    private var state: PlayerState { playerService.state }

    var body: some View {
        HStack(spacing: 12) {
            // ── Album art + now playing info ──────────────────────────────────
            nowPlayingInfo

            Spacer()

            // ── Transport controls ────────────────────────────────────────────
            transportControls

            Spacer()

            // ── Right cluster: volume + queue ─────────────────────────────────
            rightCluster
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(height: 72)
        .overlay(alignment: .topTrailing) {
            if let notice = state.resumeNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.trailing, 4)
            }
        }
        .onChange(of: state.currentItem?.id) { _, newID in
            loadArtworkIfNeeded(for: newID)
        }
    }

    // MARK: - Now Playing

    private var nowPlayingInfo: some View {
        HStack(spacing: 10) {
            artworkThumbnail
                .onTapGesture { isShowingFullscreen = true }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentItem?.displayTitle ?? "Not Playing")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(state.currentItem != nil ? .primary : .secondary)
                if case .error(let message) = state.status {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let item = state.currentItem {
                    Text(item.displayArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 100, maxWidth: 200, alignment: .leading)
        }
    }

    private var artworkThumbnail: some View {
        Group {
            if let artwork {
                artwork.resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: state.currentItem?.type_.systemImage ?? "music.note")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                // Shuffle / Repeat
                Button(action: playerService.toggleShuffle) {
                    Image(systemName: state.isShuffled ? "shuffle.circle.fill" : "shuffle")
                        .foregroundStyle(state.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(state.isShuffled ? "Shuffle: On" : "Shuffle: Off")

                // Previous
                Button(action: playerService.playPrevious) {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .disabled(state.currentItem == nil)

                // Play / Pause / Loading
                Group {
                    if state.status == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 32, height: 32)
                    } else {
                        Button(action: playerService.togglePlayPause) {
                            Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title)
                                .symbolEffect(.bounce, value: state.isPlaying)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.currentItem == nil)
                    }
                }

                // Next
                Button(action: playerService.playNext) {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .disabled(!state.hasNext)

                // Repeat
                Button(action: cycleRepeatMode) {
                    Image(systemName: state.repeatMode.systemImage)
                        .foregroundStyle(state.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
            .font(.callout)

            // Scrubber
            PlayerScrubber(
                position: Binding(
                    get: { state.positionSeconds },
                    set: { playerService.state.positionSeconds = $0 }
                ),
                duration: state.currentDuration,
                onSeek: playerService.seek(to:)
            )
            .frame(width: 300)
        }
    }

    // MARK: - Right Cluster

    private var rightCluster: some View {
        HStack(spacing: 10) {
            // Volume slider
            HStack(spacing: 4) {
                Image(systemName: state.isMuted || state.volume == 0 ? "speaker.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .onTapGesture { playerService.state.isMuted.toggle() }

                Slider(
                    value: Binding(
                        get: { Double(state.volume) },
                        set: { playerService.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .frame(width: 80)
            }

            // Visualizer micro
            if showVisualizerInMini {
                MiniSpectrumView(magnitudes: playerService.fftMagnitudes)
                    .frame(width: 40, height: 20)
                    .opacity(state.isPlaying ? 1 : 0.3)
            }
        }
    }

    // MARK: - Helpers

    private func cycleRepeatMode() {
        let modes = RepeatMode.allCases
        let current = modes.firstIndex(of: state.repeatMode) ?? 0
        playerService.state.repeatMode = modes[(current + 1) % modes.count]
    }

    private func loadArtworkIfNeeded(for itemID: String?) {
        guard let itemID, itemID != artworkItemID,
              let item = playerService.state.currentItem else {
            artwork = nil
            artworkItemID = nil
            return
        }
        artworkItemID = itemID
        Task {
            if let data = await metadataService.artwork(for: item.url),
               let nsImage = NSImage(data: data) {
                artwork = Image(nsImage: nsImage)
            } else {
                artwork = nil
            }
        }
    }
}

// MARK: - Scrubber

struct PlayerScrubber: View {
    @Binding var position: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragPosition: Double = 0

    private var displayPosition: Double { isDragging ? dragPosition : position }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { displayPosition },
                    set: { newValue in
                        dragPosition = newValue
                        isDragging = true
                    }
                ),
                in: 0...max(1, duration),
                onEditingChanged: { editing in
                    if !editing {
                        onSeek(dragPosition)
                        isDragging = false
                    }
                }
            )
            .controlSize(.mini)

            HStack {
                Text(formatTime(displayPosition))
                Spacer()
                Text("-\(formatTime(max(0, duration - displayPosition)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let h = m / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m % 60, s % 60)
        }
        return String(format: "%d:%02d", m % 60, s % 60)
    }
}

// MARK: - Mini Spectrum (visualizer thumbnail)

struct MiniSpectrumView: View {
    @Environment(\.themeService) var themeService
    let magnitudes: [Float]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<min(16, magnitudes.count), id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(themeService.visualizerColors.first ?? .accentColor)
                    .frame(width: 2, height: CGFloat(magnitudes[i]) * 20)
                    .animation(.easeOut(duration: 0.1), value: magnitudes[i])
            }
        }
    }
}

// MARK: - Fullscreen Player View

struct FullscreenPlayerView: View {
    @Environment(\.playerService)    var playerService
    @Environment(\.audiobookService) var audiobookService
    @Environment(\.themeService)     var themeService
    @Environment(\.metadataService)  var metadataService
    @Environment(\.dismiss)          var dismiss

    @State private var artwork: Image? = nil
    @State private var showingQueue = false
    @State private var showingEq = false

    private var state: PlayerState { playerService.state }

    var body: some View {
        ZStack {
            // Blurred background
            artworkBackground

            VStack(spacing: 24) {
                // Dismiss button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: { showingQueue.toggle() }) {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.plain)
                    Button(action: { showingEq.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)

                Spacer()

                // Large album art
                artworkCircle
                    .frame(width: 280, height: 280)
                    .shadow(radius: 20, y: 10)

                // Track info
                VStack(spacing: 6) {
                    Text(state.currentItem?.displayTitle ?? "Nothing Playing")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    Text(state.currentItem?.displayArtist ?? "")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    if let album = state.currentItem?.album {
                        Text(album)
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 40)

                // Scrubber
                PlayerScrubber(
                    position: Binding(
                        get: { state.positionSeconds },
                        set: { playerService.state.positionSeconds = $0 }
                    ),
                    duration: state.currentDuration,
                    onSeek: playerService.seek(to:)
                )
                .padding(.horizontal, 40)

                // Controls
                HStack(spacing: 40) {
                    Button(action: playerService.playPrevious) {
                        Image(systemName: "backward.fill").font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button(action: playerService.togglePlayPause) {
                        Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                            .symbolEffect(.bounce, value: state.isPlaying)
                    }
                    .buttonStyle(.plain)

                    Button(action: playerService.playNext) {
                        Image(systemName: "forward.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                }

                // Spectrum visualizer
                SpectrumVisualizerView(magnitudes: playerService.fftMagnitudes)
                    .frame(height: 60)
                    .padding(.horizontal, 40)
                    .opacity(state.isPlaying ? 1 : 0.4)

                Spacer()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .colorScheme(themeService.currentTheme.colorScheme)
        .onChange(of: state.currentItem?.id) { _, id in
            loadArtwork(for: id)
        }
        .sheet(isPresented: $showingQueue) {
            QueueView().frame(minWidth: 360, minHeight: 400)
        }
        .sheet(isPresented: $showingEq) {
            EqView().frame(minWidth: 400, minHeight: 300)
        }
    }

    private var artworkBackground: some View {
        ZStack {
            themeService.gradients.fullPlayerBackground
                .ignoresSafeArea()
            ThemeAmbientEffects()
            if let artwork {
                artwork.resizable().scaledToFill().ignoresSafeArea()
                    .blur(radius: 60).opacity(0.25)
            }
        }
    }

    private var artworkCircle: some View {
        Group {
            if let artwork {
                artwork.resizable().scaledToFill()
            } else {
                Circle().fill(.fill.secondary)
                    .overlay { Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.tertiary) }
            }
        }
        .clipShape(Circle())
    }

    private func loadArtwork(for itemID: String?) {
        guard let item = playerService.state.currentItem else { artwork = nil; return }
        Task {
            if let data = await metadataService.artwork(for: item.url),
               let nsImage = NSImage(data: data) {
                artwork = Image(nsImage: nsImage)
            }
        }
    }
}
