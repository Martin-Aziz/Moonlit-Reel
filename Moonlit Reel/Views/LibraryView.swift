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

    @State private var sortOrder: [KeyPathComparator<MediaItem>] = [
        .init(\.displayArtist, order: .forward),
        .init(\.displayAlbum,  order: .forward),
        .init(\.trackNumber,   order: .forward)
    ]
    @State private var selectedTrackID: String? = nil
    @State private var columnCustomization = TableColumnCustomization<MediaItem>()

    private var tracks: [MediaItem] {
        if searchService.query.isEmpty {
            return libraryService.state.allTracks
        }
        return searchService.results.map { $0.item }
    }

    var body: some View {
        Group {
            if tracks.isEmpty && !libraryService.state.isScanning {
                emptyState
            } else {
                trackTable
            }
        }
        .navigationTitle("Library")
        .navigationSubtitle("\(libraryService.state.audioTrackCount) tracks")
        .toolbar { toolbarItems }
    }

    // MARK: - Table

    private var trackTable: some View {
        Table(
            tracks,
            selection: $selectedTrackID,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("#", value: \.trackNumber.mapped { $0.map(String.init) ?? "" }) { item in
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
        ContentUnavailableView {
            Label("No Music Yet", systemImage: "music.note")
        } description: {
            Text("Add a folder containing your music files.")
        } actions: {
            Button("Add Folder") {
                Task { await libraryService.addFolderInteractively() }
            }
            .buttonStyle(.borderedProminent)
        }
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
    }

    // MARK: - Helpers

    private func playSelected(ids: Set<String>) {
        let items = tracks.filter { ids.contains($0.id) }
        playItems(items)
    }

    private func playItems(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        playerService.play(queue: tracks, startAt: tracks.firstIndex(where: { $0.id == items[0].id }) ?? 0)
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
                .foregroundStyle(isPlaying ? .tint : .primary)
        }
    }
}

// MARK: - Optional KeyPath mapping helper

private extension Optional {
    func mapped<T>(_ transform: (Wrapped) -> T) -> T? {
        self.map(transform)
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

private struct MetadataServiceKey: EnvironmentKey {
    static let defaultValue = MetadataService()
}

extension EnvironmentValues {
    var metadataService: MetadataService {
        get { self[MetadataServiceKey.self] }
        set { self[MetadataServiceKey.self] = newValue }
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
