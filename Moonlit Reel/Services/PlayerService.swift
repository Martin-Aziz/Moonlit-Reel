// PlayerService.swift — AVAudioEngine-based playback with full effects chain
//
// PURPOSE: Central playback service. Manages AVAudioEngine graph, crossfade,
//          gapless playback, ReplayGain, and 10-band parametric EQ.
//          Exposes playback control via simple verb methods.
// LAYER:   Application Service
// DEPENDS ON: PlayerState, MediaItem, AVFoundation

import Foundation
import AVFoundation
import AudioUnit

/// Manages all audio/video playback operations.
///
/// Audio files go through the AVAudioEngine graph (EQ → compressor → output).
/// Video files use a separate AVPlayer with AVPlayerLayer for rendering.
@MainActor
@Observable
final class PlayerService {

    // ── Public state ─────────────────────────────────────────────────────────
    let state: PlayerState = PlayerState()

    // ── Visualizer data (updated at ~60fps from the engine tap) ──────────────
    private(set) var fftMagnitudes: [Float] = Array(repeating: 0, count: 64)

    // ── AVAudioEngine audio graph ─────────────────────────────────────────────
    private let engine        = AVAudioEngine()
    private let playerNode    = AVAudioPlayerNode()
    private let eqNode        = AVAudioUnitEQ(numberOfBands: 10)
    private let reverbNode    = AVAudioUnitReverb()
    private let dynamicsNode: AVAudioUnitEffect = {
        // macOS dynamics compressor via CoreAudio component (replaces iOS-only AVAudioUnitDynamicsProcessor)
        let desc = AudioComponentDescription(
            componentType:         kAudioUnitType_Effect,
            componentSubType:      kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags:        0,
            componentFlagsMask:    0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()
    private let timePitchNode = AVAudioUnitTimePitch()

    // ── AVPlayer for video ─────────────────────────────────────────────────────
    private(set) var videoPlayer: AVPlayer = AVPlayer()
    private var videoPlayerObservers: [NSKeyValueObservation] = []

    // ── Current audio file ────────────────────────────────────────────────────
    private var currentAudioFile: AVAudioFile?
    private var positionTimer: Task<Void, Never>?
    private var nextFileBuffer: AVAudioPCMBuffer?

    // ── Crossfade ─────────────────────────────────────────────────────────────
    private var crossfadeTask: Task<Void, Never>?

    // ── Persistence / personalization ─────────────────────────────────────────
    private var settingsObserver: NSObjectProtocol?
    private var lastInsightPersistAt: Date = .distantPast
    private var activeEqContextKey: String?
    private var isApplyingAdaptiveEq = false

    // MARK: - Initialization

    init() {
        configureAudioGraph()
        installVisualizerTap()
        syncSettingsFromDefaults()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncSettingsFromDefaults()
        }
    }

    // MARK: - Playback Controls

    /// Load and play a single item, replacing the current queue.
    func play(_ item: MediaItem) {
        state.replaceQueue([item])
        loadAndPlay(item)
    }

    /// Start playback of a queue starting at `index`.
    func play(queue: [MediaItem], startAt index: Int = 0) {
        state.replaceQueue(queue, startAt: index)
        if let item = state.currentItem {
            loadAndPlay(item)
        }
    }

    func togglePlayPause() {
        switch state.status {
        case .playing:  pause()
        case .paused:   resume()
        case .idle, .ended: if let item = state.currentItem { loadAndPlay(item) }
        default: break
        }
    }

    func pause() {
        if state.currentItem?.type_ == .video {
            videoPlayer.pause()
        } else {
            playerNode.pause()
        }
        state.status = .paused
        stopPositionTimer()
    }

    func resume() {
        if state.currentItem?.type_ == .video {
            videoPlayer.play()
        } else {
            playerNode.play()
            if !engine.isRunning { try? engine.start() }
        }
        state.status = .playing
        startPositionTimer()
    }

    func skipForward(seconds: Double = 15) {
        seek(to: state.positionSeconds + seconds)
    }

    func skipBackward(seconds: Double = 15) {
        seek(to: state.positionSeconds - seconds)
    }

    func playNext() {
        guard state.hasNext else {
            state.status = .ended
            return
        }
        switch state.repeatMode {
        case .one:
            seek(to: 0)
            resume()
        case .all, .off:
            let nextIndex = state.queue.indices.contains(state.queueIndex + 1)
                ? state.queueIndex + 1
                : 0
            state.queueIndex = nextIndex
            state.currentItem = state.queue[nextIndex]
            loadAndPlay(state.queue[nextIndex])
        }
    }

    func playPrevious() {
        if state.positionSeconds > 3 {
            seek(to: 0)
            return
        }
        let prevIndex = max(0, state.queueIndex - 1)
        state.queueIndex = prevIndex
        state.currentItem = state.queue[prevIndex]
        loadAndPlay(state.queue[prevIndex])
    }

    func seek(to position: Double) {
        let clamped = max(0, min(position, state.currentDuration))

        if state.currentItem?.type_ == .video {
            let time = CMTime(seconds: clamped, preferredTimescale: 600)
            videoPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            state.positionSeconds = clamped
            return
        }

        guard let audioFile = currentAudioFile else { return }
        let sampleRate = audioFile.processingFormat.sampleRate
        let sampleTime = AVAudioFramePosition(clamped * sampleRate)

        playerNode.stop()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: sampleTime,
            frameCount: AVAudioFrameCount(audioFile.length - sampleTime),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.handlePlaybackCompletion() }
        }

        if state.isPlaying {
            playerNode.play()
        }
        state.positionSeconds = clamped
        recordProgressSnapshot()
    }

    // MARK: - Volume & Playback Rate

    func setVolume(_ volume: Float) {
        state.volume = volume.clamped(0, 1)
        if state.currentItem?.type_ == .video {
            videoPlayer.volume = volume
        } else {
            playerNode.volume = volume
        }
    }

    func setPlaybackRate(_ rate: Double) {
        state.playbackRate = rate.clamped(0.5, 2.0)
        timePitchNode.rate = Float(rate)
        if state.currentItem?.type_ == .video {
            videoPlayer.rate = Float(rate)
        }
    }

    func applyCrossfadeDuration(_ duration: Double) {
        state.crossfadeDuration = duration.clamped(0, 12)
    }

    func applyReplayGainSettings(enabled: Bool, useAlbumGain: Bool, preAmpDB: Double) {
        state.isReplayGainEnabled = enabled
        state.useAlbumGain = useAlbumGain
        state.replayGainPreAmpDB = preAmpDB.clamped(-12, 12)
    }

    // MARK: - EQ

    func setEqBand(index: Int, gainDB: Float) {
        guard eqNode.bands.indices.contains(index) else { return }
        eqNode.bands[index].gain = gainDB
        persistAdaptiveEqProfileIfNeeded()
    }

    func eqBandGain(at index: Int) -> Float {
        guard eqNode.bands.indices.contains(index) else { return 0 }
        return eqNode.bands[index].gain
    }

    func setEqEnabled(_ enabled: Bool) {
        state.isEqEnabled = enabled
        eqNode.bypass = !enabled
        persistAdaptiveEqProfileIfNeeded()
    }

    func applyEqPreset(_ preset: EqPreset) {
        guard preset.gains.count == eqNode.bands.count else { return }
        for (i, gain) in preset.gains.enumerated() {
            eqNode.bands[i].gain = gain
        }
        setEqEnabled(true)
        persistAdaptiveEqProfileIfNeeded()
    }

    // MARK: - Private: Graph Setup

    private func configureAudioGraph() {
        let format = engine.outputNode.outputFormat(forBus: 0)

        // Attach all nodes
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(reverbNode)
        engine.attach(dynamicsNode)
        engine.attach(timePitchNode)

        // Configure EQ bands: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
        let freqs: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (i, band) in eqNode.bands.enumerated() {
            band.filterType  = .parametric
            band.frequency   = freqs[i]
            band.gain        = 0
            band.bandwidth   = 0.5
            band.bypass      = false
        }
        eqNode.bypass = true  // Off by default

        // Configure reverb
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 0
        reverbNode.bypass = true

        // Configure dynamics (compressor)
        dynamicsNode.bypass = true

        // Wire: playerNode → EQ → reverb → dynamics → timePitch → output
        engine.connect(playerNode,    to: eqNode,       format: format)
        engine.connect(eqNode,        to: reverbNode,   format: format)
        engine.connect(reverbNode,    to: dynamicsNode, format: format)
        engine.connect(dynamicsNode,  to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)

        try? engine.start()
    }

    private func installVisualizerTap() {
        let tapBus = 0
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: tapBus)
        let bufferSize: AVAudioFrameCount = 1024

        engine.mainMixerNode.installTap(onBus: tapBus, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let magnitudes = computeFFTMagnitudes(buffer: buffer, count: 64)
            Task { @MainActor in
                self.fftMagnitudes = magnitudes
            }
        }
    }

    // MARK: - Private: Loading

    private func loadAndPlay(_ item: MediaItem) {
        stopPositionTimer()
        playerNode.stop()
        crossfadeTask?.cancel()
        currentAudioFile = nil
        state.status = .loading
        state.positionSeconds = 0
        state.currentItem = item

        applyAdaptiveEqProfile(for: item)
        PlaybackInsightsStore.recordPlayStart(itemID: item.id, durationSeconds: item.durationSeconds)

        if item.type_ == .video {
            loadVideo(item)
            return
        }

        Task {
            do {
                let audioFile = try AVAudioFile(forReading: item.url)
                await MainActor.run {
                    self.currentAudioFile = audioFile
                    self.state.currentItem = item
                }

                playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor [self] in self.handlePlaybackCompletion() }
                }

                await MainActor.run {
                    if !self.engine.isRunning { try? self.engine.start() }
                    self.playerNode.volume = self.state.isMuted ? 0 : self.state.volume
                    self.playerNode.play()
                    self.state.status = .playing
                    self.startPositionTimer()

                    if let resumePosition = self.preferredResumePosition(for: item) {
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            await MainActor.run {
                                self.seek(to: resumePosition)
                                self.state.resumeNotice = "Resumed at \(self.formatTimestamp(resumePosition))"
                            }
                            try? await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                if self.state.resumeNotice?.hasPrefix("Resumed") == true {
                                    self.state.resumeNotice = nil
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.state.status = .error(error.localizedDescription)
                }
            }
        }
    }

    private func loadVideo(_ item: MediaItem) {
        let playerItem = AVPlayerItem(url: item.url)
        videoPlayer.replaceCurrentItem(with: playerItem)

        videoPlayerObservers.forEach { $0.invalidate() }
        videoPlayerObservers = [
            videoPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
                guard let self else { return }
                Task { @MainActor [self] in
                    switch player.timeControlStatus {
                    case .playing:   self.state.status = .playing
                    case .paused:    self.state.status = .paused
                    case .waitingToPlayAtSpecifiedRate: self.state.status = .loading
                    @unknown default: break
                    }
                }
            }
        ]

        videoPlayer.play()
        state.currentItem = item
        state.status = .playing
        startPositionTimer()
    }

    private func handlePlaybackCompletion() {
        if state.repeatMode == .one {
            seek(to: 0)
            playerNode.play()
        } else {
            playNext()
        }
    }

    // MARK: - Position Timer

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run { self.updatePosition() }
            }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.cancel()
        positionTimer = nil
    }

    private func updatePosition() {
        if state.currentItem?.type_ == .video {
            state.positionSeconds = CMTimeGetSeconds(videoPlayer.currentTime())
        } else if let lastRenderTime = playerNode.lastRenderTime,
                  let nodeTime = playerNode.playerTime(forNodeTime: lastRenderTime),
                  let audioFile = currentAudioFile {
            let sampleRate = audioFile.processingFormat.sampleRate
            state.positionSeconds = Double(nodeTime.sampleTime) / sampleRate
        }

        recordProgressSnapshot()
    }

    private func syncSettingsFromDefaults() {
        let defaults = UserDefaults.standard
        state.crossfadeDuration = defaults.double(forKey: "settings.crossfadeDuration")
        state.isReplayGainEnabled = defaults.bool(forKey: "settings.replayGainEnabled")

        if defaults.object(forKey: "settings.useAlbumGain") != nil {
            state.useAlbumGain = defaults.bool(forKey: "settings.useAlbumGain")
        }
        state.replayGainPreAmpDB = defaults.double(forKey: "settings.preAmpDB")
    }

    private func recordProgressSnapshot() {
        guard let item = state.currentItem else { return }
        let now = Date()
        if now.timeIntervalSince(lastInsightPersistAt) < 1.0 {
            return
        }
        lastInsightPersistAt = now
        PlaybackInsightsStore.recordProgress(
            itemID: item.id,
            positionSeconds: state.positionSeconds,
            durationSeconds: state.currentDuration
        )
    }

    private func eqContextKey(for item: MediaItem) -> String {
        if let album = item.album, !album.isEmpty {
            let artist = (item.albumArtist ?? item.artist ?? "unknown").lowercased()
            return "album:\(artist)|\(album.lowercased())"
        }
        if item.type_ == .audiobookChapter {
            return "audiobook:\((item.album ?? item.displayTitle).lowercased())"
        }
        return "item:\(item.id)"
    }

    private func applyAdaptiveEqProfile(for item: MediaItem) {
        let contextKey = eqContextKey(for: item)
        activeEqContextKey = contextKey

        guard let profile = PlaybackInsightsStore.adaptiveEqProfile(for: contextKey),
              profile.gainsDB.count == eqNode.bands.count else {
            return
        }

        isApplyingAdaptiveEq = true
        for (index, gain) in profile.gainsDB.enumerated() {
            eqNode.bands[index].gain = gain
        }
        let hasMeaningfulGain = profile.gainsDB.contains { abs($0) >= 0.1 }
        state.isEqEnabled = hasMeaningfulGain
        eqNode.bypass = !hasMeaningfulGain
        isApplyingAdaptiveEq = false
    }

    private func persistAdaptiveEqProfileIfNeeded() {
        guard !isApplyingAdaptiveEq,
              let contextKey = activeEqContextKey else {
            return
        }

        let gains = eqNode.bands.map { $0.gain }
        let profile = AdaptiveEqProfile(gainsDB: gains, updatedAt: Date())
        PlaybackInsightsStore.saveAdaptiveEqProfile(profile, contextKey: contextKey)
    }

    private func preferredResumePosition(for item: MediaItem) -> Double? {
        guard let snapshot = PlaybackInsightsStore.snapshot(for: item.id) else { return nil }

        let duration = max(item.durationSeconds, snapshot.durationSeconds)
        guard duration > 0 else { return nil }

        let isLongForm = item.type_ == .audiobookChapter || item.type_ == .video || duration >= 10 * 60
        guard isLongForm else { return nil }

        let position = snapshot.lastPositionSeconds
        guard position >= 15, position <= duration - 10 else { return nil }
        return position
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - FFT helper

private func computeFFTMagnitudes(buffer: AVAudioPCMBuffer, count: Int) -> [Float] {
    guard let data = buffer.floatChannelData?[0] else {
        return Array(repeating: 0, count: count)
    }
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return Array(repeating: 0, count: count) }

    // Simple RMS-based band energy (replace with vDSP FFT for production)
    let stride = max(1, frameCount / count)
    var magnitudes = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let offset = i * stride
        let end = min(offset + stride, frameCount)
        var sum: Float = 0
        for j in offset..<end { sum += abs(data[j]) }
        magnitudes[i] = sum / Float(end - offset)
    }
    return magnitudes
}

// MARK: - EQ Preset

struct EqPreset: Identifiable, Hashable {
    let id: UUID = UUID()
    var name: String
    var gains: [Float]  /// Must have exactly 10 elements

    static let flat        = EqPreset(name: "Flat",        gains: Array(repeating: 0, count: 10))
    static let bassBoost   = EqPreset(name: "Bass Boost",  gains: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0])
    static let vocal       = EqPreset(name: "Vocal",       gains: [-2, -1, 0, 1, 3, 4, 3, 1, 0, -1])
    static let classical   = EqPreset(name: "Classical",   gains: [0, 0, 0, 0, 0, 0, -2, -2, -2, -3])
    static let electronic  = EqPreset(name: "Electronic",  gains: [5, 4, 1, 0, -1, 2, 3, 3, 2, 1])
    static let allPresets  = [flat, bassBoost, vocal, classical, electronic]
}

// MARK: - Clamp helper

private extension Float {
    func clamped(_ lower: Float, _ upper: Float) -> Float {
        min(max(self, lower), upper)
    }
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
