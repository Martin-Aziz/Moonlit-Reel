// LibraryView.swift — All-tracks library browser with sort and grouping
//
// PURPOSE: Shows all audio tracks in the library as a sortable, filterable list.
//          Supports drag-to-queue and double-click-to-play.
// LAYER:   Presentation

import SwiftUI

struct LibraryView: View {
    @Environment(\.libraryService) var libraryService
    @Environment(\.playerService)  var playerService
    @Environment(\.searchService)  var searchService
    @Environment(\.themeService)   var themeService

    @State private var sortOrder: [KeyPathComparator<MediaItem>] = [
        .init(\.displayArtist, order: .forward),
        .init(\.displayAlbum,  order: .forward),
        .init(\.trackNumber,   order: .forward)
    ]
    @State private var selectedTrackID: String? = nil
    @State private var columnCustomization = TableColumnCustomization<MediaItem>()
    @State private var showingScanReport = false

    private var tracks: [MediaItem] {
        if searchService.query.isEmpty {
            return libraryService.state.allTracks
        }
        var seen: Set<String> = []
        var unique: [MediaItem] = []
        for result in searchService.results {
            if seen.insert(result.item.id).inserted {
                unique.append(result.item)
            }
        }
        return unique
    }

    private var allItemsByID: [String: MediaItem] {
        let allItems = libraryService.state.allTracks + libraryService.state.allVideos
        return Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    private var continueListeningItems: [MediaItem] {
        let ids = PlaybackInsightsStore.continueItemIDs(limit: 8)
        let lookup = allItemsByID
        return ids.compactMap { lookup[$0] }
    }

    var body: some View {
        Group {
            if tracks.isEmpty && !libraryService.state.isScanning {
                emptyState
            } else {
                libraryContent
            }
        }
        .navigationTitle("Library")
        .navigationSubtitle("\(libraryService.state.audioTrackCount) tracks")
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingScanReport) {
            if let report = libraryService.state.latestScanReport {
                ScanReportDetailView(report: report)
            }
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 12) {
            if !continueListeningItems.isEmpty {
                continueListeningStrip
                    .padding(.horizontal)
                    .padding(.top, 10)
            }

            if let report = libraryService.state.latestScanReport {
                scanReportBanner(report)
                    .padding(.horizontal)
            }

            trackTable
        }
    }

    // MARK: - Table

    private var trackTable: some View {
        Table(
            tracks,
            selection: $selectedTrackID,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("#") { item in
                Text(item.trackNumber.map(String.init) ?? "")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 30, ideal: 36, max: 50)
            .customizationID("trackNum")

            TableColumn("Title", value: \.displayTitle) { item in
                TrackRowView(item: item, isPlaying: playerService.state.currentItem?.id == item.id)
            }
            .customizationID("title")

            TableColumn("Artist", value: \.displayArtist)
                .customizationID("artist")

            TableColumn("Album", value: \.displayAlbum)
                .customizationID("album")

            TableColumn("Duration") { item in
                Text(item.formattedDuration)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60, max: 80)
            .customizationID("duration")

            TableColumn("Year") { item in
                Text(item.year.map(String.init) ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 50, max: 60)
            .customizationID("year")
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            playSelected(ids: ids)
        }
        .onChange(of: sortOrder) { _, newOrder in
            // Table manages its own sort — no action needed
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        let items = tracks.filter { ids.contains($0.id) }
        Button("Play Now") { playItems(items) }
        Button("Play Next") { items.forEach { playerService.state.insertNext($0) } }
        Button("Add to Queue") { items.forEach { playerService.state.appendToQueue($0) } }
        Divider()
        Button("Get Info", action: {})
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            LogoView(size: 80, showShadow: true)

            VStack(spacing: 8) {
                Text("No Music Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(themeService.colors.primary)

                Text("Add a folder containing your music files to get started.")
                    .font(.body)
                    .foregroundColor(themeService.colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Button {
                Task { await libraryService.addFolderInteractively() }
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button(action: { Task { await libraryService.addFolderInteractively() } }) {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
        }
        ToolbarItem {
            Button(action: { Task { await libraryService.rescanAll() } }) {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
        ToolbarItem {
            Menu {
                Button("15 minutes") { composeSession(minutes: 15) }
                Button("25 minutes") { composeSession(minutes: 25) }
                Button("45 minutes") { composeSession(minutes: 45) }
                Button("60 minutes") { composeSession(minutes: 60) }
            } label: {
                Label("Compose Session", systemImage: "timer")
            }
        }
    }

    // MARK: - Helpers

    private func playSelected(ids: Set<String>) {
        let items = tracks.filter { ids.contains($0.id) }
        playItems(items)
    }

    private func playItems(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        let first = items[0]
        if let jump = searchService.results.first(where: { $0.item.id == first.id })?.jumpToSeconds {
            playerService.play(first)
            if jump > 0 {
                Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    await MainActor.run {
                        playerService.seek(to: jump)
                    }
                }
            }
            return
        }

        playerService.play(queue: tracks, startAt: tracks.firstIndex(where: { $0.id == first.id }) ?? 0)
    }

    private func composeSession(minutes: Int) {
        let targetSeconds = Double(max(5, minutes)) * 60
        let candidates = (libraryService.state.allTracks + libraryService.state.allVideos)
            .filter { $0.isAudio && $0.durationSeconds > 0 }

        guard !candidates.isEmpty else { return }

        let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let seedIDs = PlaybackInsightsStore.sessionSeedItemIDs(limit: 40)

        var queue: [MediaItem] = []
        var seen: Set<String> = []
        var total: Double = 0

        for id in seedIDs {
            guard let item = lookup[id], !seen.contains(item.id) else { continue }
            queue.append(item)
            seen.insert(item.id)
            total += item.durationSeconds
            if total >= targetSeconds * 0.7 { break }
        }

        let remaining = candidates
            .filter { !seen.contains($0.id) }
            .sorted { $0.durationSeconds < $1.durationSeconds }

        for item in remaining {
            if total >= targetSeconds * 1.15 { break }
            queue.append(item)
            seen.insert(item.id)
            total += item.durationSeconds
        }

        guard !queue.isEmpty else { return }
        playerService.play(queue: queue, startAt: 0)
    }

    private func scanReportBanner(_ report: LibraryScanReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Import Confidence Center", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Button("Details") { showingScanReport = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack(spacing: 14) {
                metricPill("Imported", value: "\(report.importedCount)", tint: .green)
                metricPill("Failed", value: "\(report.failedCount)", tint: report.failedCount == 0 ? .secondary : .red)
                metricPill("Unsupported", value: "\(report.skippedUnsupportedCount)", tint: .orange)
                metricPill("Duration", value: String(format: "%.1fs", report.durationSeconds), tint: .blue)
            }

            Text(URL(fileURLWithPath: report.rootPath).lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metricPill(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private var continueListeningStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Listening")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(continueListeningItems) { item in
                        continueCard(item)
                            .onTapGesture {
                                playerService.play(item)
                            }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func continueCard(_ item: MediaItem) -> some View {
        let snapshot = PlaybackInsightsStore.snapshot(for: item.id)
        let progress = snapshot?.progressFraction ?? 0
        let position = snapshot?.lastPositionSeconds ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(item.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text("\(formatShort(position)) / \(item.formattedDuration)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatShort(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Track Row

private struct TrackRowView: View {
    let item: MediaItem
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .foregroundStyle(.tint)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }
            Text(item.displayTitle)
                .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
    }
}

private struct ScanReportDetailView: View {
    let report: LibraryScanReport
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Root") { Text(report.rootPath).lineLimit(1) }
                    LabeledContent("Imported") { Text("\(report.importedCount)") }
                    LabeledContent("Failed") { Text("\(report.failedCount)") }
                    LabeledContent("Unsupported") { Text("\(report.skippedUnsupportedCount)") }
                    LabeledContent("Duration") { Text(String(format: "%.2f sec", report.durationSeconds)).monospacedDigit() }
                }

                if !report.unsupportedExamples.isEmpty {
                    Section("Unsupported Examples") {
                        ForEach(report.unsupportedExamples, id: \.self) { sample in
                            Text(sample)
                        }
                    }
                }

                if !report.parseFailures.isEmpty {
                    Section("Parse Failures") {
                        ForEach(report.parseFailures) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.filePath)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(issue.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan Report")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }
}

// MARK: - Album Grid View

struct AlbumGridView: View {
    @Environment(\.libraryService) var libraryService
    @Environment(\.playerService)  var playerService

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(libraryService.state.albumGroups) { album in
                    AlbumCardView(album: album)
                        .onTapGesture(count: 2) {
                            playerService.play(queue: album.tracks, startAt: 0)
                        }
                }
            }
            .padding()
        }
        .navigationTitle("Albums")
        .navigationSubtitle("\(libraryService.state.albumGroups.count) albums")
    }
}

private struct AlbumCardView: View {
    let album: AlbumGroup
    @Environment(\.metadataService) var metadataService
    @State private var artwork: Image? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkView
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4, y: 2)

            Text(album.title)
                .fontWeight(.medium)
                .lineLimit(2)
                .font(.caption)
            Text(album.artist)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .font(.caption2)
        }
        .task {
            await loadArtwork()
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork {
                artwork.resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }

    private func loadArtwork() async {
        guard let firstTrack = album.tracks.first else { return }
        if let data = await metadataService.artwork(for: firstTrack.url),
           let nsImage = NSImage(data: data) {
            artwork = Image(nsImage: nsImage)
        }
    }
}

// MARK: - Artist List View

struct ArtistListView: View {
    @Environment(\.libraryService) var libraryService

    var body: some View {
        List(libraryService.state.artistGroups) { artist in
            NavigationLink(artist.name) {
                ArtistDetailView(artist: artist)
            }
            .badge(artist.trackCount)
        }
        .navigationTitle("Artists")
        .navigationSubtitle("\(libraryService.state.artistGroups.count) artists")
    }
}

private struct ArtistDetailView: View {
    let artist: ArtistGroup
    @Environment(\.playerService) var playerService

    var body: some View {
        List {
            ForEach(artist.albums) { album in
                Section(album.title) {
                    ForEach(album.tracks) { track in
                        TrackRowView(item: track, isPlaying: playerService.state.currentItem?.id == track.id)
                            .onTapGesture(count: 2) {
                                playerService.play(queue: album.tracks,
                                    startAt: album.tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
                            }
                    }
                }
            }
        }
        .navigationTitle(artist.name)
    }
}
