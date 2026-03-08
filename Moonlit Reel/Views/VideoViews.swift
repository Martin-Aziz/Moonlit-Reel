// VideoViews.swift — Video library grid and full-screen player
//
// PURPOSE: Displays video library and provides hardware-accelerated video playback
//          with subtitle overlay, aspect ratio control, and transport controls.
// LAYER:   Presentation

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Video Library

struct VideoLibraryView: View {
    @Environment(\.libraryService) var libraryService
    @Environment(\.playerService)  var playerService

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280))]
    @State private var selectedVideo: MediaItem? = nil

    var body: some View {
        Group {
            if libraryService.state.allVideos.isEmpty {
                emptyState
            } else {
                videoGrid
            }
        }
        .navigationTitle("Videos")
        .navigationSubtitle("\(libraryService.state.videoCount) videos")
        .sheet(item: $selectedVideo) { video in
            VideoPlayerView(item: video)
        }
    }

    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(libraryService.state.allVideos) { video in
                    VideoThumbnailCard(video: video) {
                        selectedVideo = video
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Videos", systemImage: "film")
        } description: {
            Text("Add a folder containing video files (MP4, MKV, MOV, AVI…).")
        } actions: {
            Button("Add Folder") {
                Task { await libraryService.addFolderInteractively() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Video Thumbnail Card

private struct VideoThumbnailCard: View {
    let video: MediaItem
    let onPlay: () -> Void

    @State private var thumbnail: Image? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Group {
                    if let thumbnail {
                        thumbnail.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.fill.secondary)
                            .overlay {
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            .onTapGesture(count: 2, perform: onPlay)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.displayTitle)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .font(.callout)
                HStack {
                    Text(video.formattedDuration)
                    if let codec = video.codec {
                        Text("·").foregroundStyle(.tertiary)
                        Text(codec).foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let asset = AVURLAsset(url: video.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        let time = CMTime(seconds: 5, preferredTimescale: 600)
        if let image = try? await generator.image(at: time).image {
            thumbnail = Image(decorative: image, scale: 1)
        }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let item: MediaItem

    @Environment(\.playerService) var playerService
    @Environment(\.dismiss)       var dismiss

    @State private var subtitleTrackURL: URL? = nil
    @State private var currentSubtitle: String = ""
    @State private var isShowingControls = true
    @State private var controlsTimer: Task<Void, Never>? = nil
    @State private var aspectRatio: AspectRatioMode = .fit

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── AVPlayer Layer ────────────────────────────────────────────────
            VideoPlayerContainer(player: playerService.videoPlayer, aspectRatio: aspectRatio)
                .onTapGesture { toggleControls() }

            // ── Subtitle overlay ─────────────────────────────────────────────
            if !currentSubtitle.isEmpty {
                VStack {
                    Spacer()
                    SubtitleOverlayView(text: currentSubtitle)
                        .padding(.bottom, isShowingControls ? 80 : 20)
                }
            }

            // ── Controls overlay ─────────────────────────────────────────────
            if isShowingControls {
                videoControls
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            playerService.play(item)
            detectSubtitleFile()
            scheduleControlsHide()
        }
        .onDisappear {
            playerService.pause()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active: showControls()
            case .ended:  scheduleControlsHide()
            }
        }
    }

    // MARK: - Controls

    private var videoControls: some View {
        VStack {
            // ── Top bar ──────────────────────────────────────────────────────
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Spacer()

                Text(item.displayTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Spacer()

                // Aspect ratio picker
                Menu {
                    ForEach(AspectRatioMode.allCases) { mode in
                        Button(mode.rawValue) { aspectRatio = mode }
                    }
                } label: {
                    Image(systemName: "rectangle.arrowtriangle.2.outward")
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)

                // Subtitle toggle
                if subtitleTrackURL != nil {
                    Button(action: {}) {
                        Image(systemName: "captions.bubble.fill")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            ))

            Spacer()

            // ── Bottom bar ───────────────────────────────────────────────────
            VStack(spacing: 8) {
                // Scrubber
                PlayerScrubber(
                    position: Binding(
                        get: { playerService.state.positionSeconds },
                        set: { playerService.state.positionSeconds = $0 }
                    ),
                    duration: playerService.state.currentDuration,
                    onSeek: playerService.seek(to:)
                )
                .accentColor(.white)

                // Transport
                HStack(spacing: 24) {
                    Button(action: playerService.playPrevious) {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button(action: { playerService.skipBackward(seconds: 10) }) {
                        Image(systemName: "gobackward.10")
                    }
                    .buttonStyle(.plain)

                    Button(action: playerService.togglePlayPause) {
                        Image(systemName: playerService.state.isPlaying
                            ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                    }
                    .buttonStyle(.plain)

                    Button(action: { playerService.skipForward(seconds: 10) }) {
                        Image(systemName: "goforward.10")
                    }
                    .buttonStyle(.plain)

                    Button(action: playerService.playNext) {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Volume
                    Slider(
                        value: Binding(
                            get: { Double(playerService.state.volume) },
                            set: { playerService.setVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 100)
                    .accentColor(.white)
                }
                .foregroundStyle(.white)
            }
            .padding()
            .background(LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    // MARK: - Helpers

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingControls.toggle()
        }
        if isShowingControls { scheduleControlsHide() }
    }

    private func showControls() {
        controlsTimer?.cancel()
        withAnimation { isShowingControls = true }
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { isShowingControls = false }
        }
    }

    private func detectSubtitleFile() {
        let srtURL = item.url.deletingPathExtension().appendingPathExtension("srt")
        if FileManager.default.fileExists(atPath: srtURL.path) {
            subtitleTrackURL = srtURL
        }
    }
}

// MARK: - AVPlayer container (NSViewRepresentable)

private struct VideoPlayerContainer: NSViewRepresentable {
    let player: AVPlayer
    let aspectRatio: AspectRatioMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = aspectRatio.avGravity
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVPlayerLayer)?.videoGravity = aspectRatio.avGravity
    }
}

// MARK: - Subtitle Overlay

private struct SubtitleOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .default, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 40)
    }
}

// MARK: - Aspect Ratio

enum AspectRatioMode: String, CaseIterable, Identifiable {
    case fit    = "Fit"
    case fill   = "Fill"
    case s16x9  = "16:9"
    case s4x3   = "4:3"
    case s235   = "2.35:1"

    var id: String { rawValue }

    var avGravity: AVLayerVideoGravity {
        switch self {
        case .fit:   return .resizeAspect
        case .fill:  return .resizeAspectFill
        default:     return .resizeAspect
        }
    }
}
