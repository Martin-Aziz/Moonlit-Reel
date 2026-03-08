// VisualizerAndUtilityViews.swift — Spectrum visualizer, EQ panel, Queue, Settings
//
// PURPOSE: Bundles the visualizer, EQ panel, queue management, and settings screen.
// LAYER:   Presentation

import SwiftUI

// MARK: - Spectrum Visualizer

struct SpectrumVisualizerView: View {
    @Environment(\.themeService) var themeService

    let magnitudes: [Float]
    var barCount: Int = 64

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<min(barCount, magnitudes.count), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barGradient(index: i, total: barCount))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, CGFloat(magnitudes[i]) * 60))
                    .animation(.easeOut(duration: themeService.animations.barAnimationDuration), value: magnitudes[i])
            }
        }
        .drawingGroup()  // GPU-efficient compositing
    }

    private func barGradient(index: Int, total: Int) -> LinearGradient {
        let colors = themeService.visualizerColors
        let colorIndex = Int(Double(index) / Double(total) * Double(colors.count - 1))
        let color = colors[min(colorIndex, colors.count - 1)]

        return LinearGradient(
            colors: [color, color.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - EQ View

struct EqView: View {
    @Environment(\.playerService) var playerService
    @State private var selectedPreset: EqPreset? = nil

    private let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Equalizer")
                .font(.title3)
                .fontWeight(.semibold)

            Toggle("EQ Enabled", isOn: Binding(
                get: { playerService.state.isEqEnabled },
                set: { playerService.setEqEnabled($0) }
            ))

            // Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqPreset.allPresets) { preset in
                        Button(preset.name) {
                            selectedPreset = preset
                            playerService.applyEqPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(selectedPreset?.name == preset.name ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
            }

            // Band Sliders
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<10, id: \.self) { idx in
                    EqBandSlider(
                        label: bandLabels[idx],
                        value: Binding(
                            get: {
                                Double(playerService.state.isEqEnabled ? 0 : 0)
                            },
                            set: { playerService.setEqBand(index: idx, gainDB: Float($0)) }
                        )
                    )
                }
            }
            .frame(height: 180)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 320)
    }
}

private struct EqBandSlider: View {
    let label: String
    @Binding var value: Double   // -12 to +12 dB

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: value == 0 ? "0" : "%+.0f", value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(height: 14)

            Slider(value: $value, in: -12...12)
                .rotationEffect(.degrees(-90))
                .frame(width: 120, height: 24)
                .frame(width: 24, height: 120)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Queue View

struct QueueView: View {
    @Environment(\.playerService) var playerService
    private var state: PlayerState { playerService.state }

    var body: some View {
        VStack(spacing: 0) {
            queueHeader
            Divider()
            if state.queue.isEmpty {
                ContentUnavailableView("Queue is Empty", systemImage: "list.number",
                    description: Text("Add tracks from the Library to start a queue."))
            } else {
                queueList
            }
        }
        .navigationTitle("Queue")
    }

    private var queueHeader: some View {
        HStack {
            Text("\(state.queue.count) tracks")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear", role: .destructive) {
                playerService.state.replaceQueue([])
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var queueList: some View {
        List {
            ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, track in
                QueueTrackRow(track: track, isPlaying: index == state.queueIndex, index: index)
                    .onTapGesture(count: 2) {
                        playerService.state.queueIndex = index
                        playerService.state.currentItem = track
                        playerService.play(queue: state.queue, startAt: index)
                    }
            }
            .onMove { source, destination in
                playerService.state.moveQueueItems(from: source, to: destination)
            }
            .onDelete { offsets in
                playerService.state.removeFromQueue(at: offsets)
            }
        }
        .listStyle(.plain)
    }
}

private struct QueueTrackRow: View {
    let track: MediaItem
    let isPlaying: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(width: 16)
            } else {
                Text("\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            Text(track.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.themeService) var themeService

    @AppStorage("settings.crossfadeDuration")     var crossfadeDuration: Double = 0
    @AppStorage("settings.replayGainEnabled")     var replayGainEnabled: Bool = false
    @AppStorage("settings.useAlbumGain")          var useAlbumGain: Bool = true
    @AppStorage("settings.preAmpDB")              var preAmpDB: Double = 0
    @AppStorage("settings.httpRemoteEnabled")     var httpRemoteEnabled: Bool = false
    @AppStorage("settings.httpRemotePort")        var httpRemotePort: Int = 7177
    @AppStorage("settings.showVisualizerInMini")  var showVisualizerInMini: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                // ── Playback ─────────────────────────────────────────────────
                Section("Playback") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Crossfade")
                            Spacer()
                            Text("\(crossfadeDuration, specifier: "%.0f") sec")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $crossfadeDuration, in: 0...12, step: 0.5)
                    }
                }

                // ── Audio ────────────────────────────────────────────────────
                Section("Audio Normalization") {
                    Toggle("ReplayGain 2.0", isOn: $replayGainEnabled)
                    if replayGainEnabled {
                        Picker("Mode", selection: $useAlbumGain) {
                            Text("Album Gain").tag(true)
                            Text("Track Gain").tag(false)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pre-amp")
                                Spacer()
                                Text("\(preAmpDB, specifier: "%+.1f") dB")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $preAmpDB, in: -12...12, step: 0.5)
                        }
                    }
                }

                // ── Appearance ───────────────────────────────────────────────
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { themeService.currentTheme },
                        set: { themeService.setTheme($0) }
                    )) {
                        ForEach(Theme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show Visualizer in Mini Player", isOn: $showVisualizerInMini)
                }

                // ── Developer ────────────────────────────────────────────────
                Section("Developer") {
                    Toggle("Local HTTP Remote Control", isOn: $httpRemoteEnabled)
                    if httpRemoteEnabled {
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("Port", value: $httpRemotePort, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        Text("Browse to http://localhost:\(httpRemotePort) on your local network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── About ────────────────────────────────────────────────────
                Section("About") {
                    LogoWithText()

                    Divider()

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}
