// LibraryState.swift — Observable library collection state
//
// PURPOSE: All library data (tracks, albums, artists, playlists) in one
//          @Observable context, minimizing redundant data traversal.
// LAYER:   Domain / Application

import Foundation

/// Grouping of tracks by album.
struct AlbumGroup: Identifiable, Hashable, Sendable {
    var id: String          /// album title + album artist (normalized)
    var title: String
    var artist: String
    var year: Int?
    var tracks: [MediaItem]
    var artworkItemID: String?  /// ID of the first track with artwork

    var durationSeconds: Double { tracks.reduce(0) { $0 + $1.durationSeconds } }
    var trackCount: Int { tracks.count }
}

/// Grouping of tracks/albums by artist.
struct ArtistGroup: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var albums: [AlbumGroup]
    var trackCount: Int { albums.reduce(0) { $0 + $1.trackCount } }
}

/// The complete library state, updated incrementally from scanner events.
@Observable
final class LibraryState {
    // ── Raw collections ──────────────────────────────────────────────────────
    private(set) var allTracks: [MediaItem] = []
    private(set) var allVideos: [MediaItem] = []
    private(set) var audiobooks: [AudiobookItem] = []

    // ── Grouped views ────────────────────────────────────────────────────────
    private(set) var albumGroups: [AlbumGroup] = []
    private(set) var artistGroups: [ArtistGroup] = []

    // ── Playlists ────────────────────────────────────────────────────────────
    var playlists: [Playlist] = []
    var smartPlaylists: [SmartPlaylist] = []

    // ── Library roots ─────────────────────────────────────────────────────────
    var libraryRootURLs: [URL] = []

    // ── Scan state ───────────────────────────────────────────────────────────
    var isScanning: Bool = false
    var scanProgress: Double = 0   /// 0.0–1.0
    var lastScanDate: Date?

    // ── Computed track counts ────────────────────────────────────────────────
    var audioTrackCount: Int { allTracks.count }
    var videoCount: Int { allVideos.count }
    var audiobookCount: Int { audiobooks.count }
    var totalTrackCount: Int { allTracks.count + allVideos.count }

    // ── Mutation ─────────────────────────────────────────────────────────────

    func upsert(_ item: MediaItem) {
        switch item.type_ {
        case .video:
            if let i = allVideos.firstIndex(where: { $0.id == item.id }) {
                allVideos[i] = item
            } else {
                allVideos.append(item)
                allVideos.sort { $0.displayTitle < $1.displayTitle }
            }
        case .audio, .audiobookChapter:
            if let i = allTracks.firstIndex(where: { $0.id == item.id }) {
                allTracks[i] = item
            } else {
                allTracks.append(item)
            }
            rebuildGroupedViews()
        }
    }

    func remove(id: String) {
        allTracks.removeAll { $0.id == id }
        allVideos.removeAll { $0.id == id }
        rebuildGroupedViews()
    }

    func upsertAudiobook(_ book: AudiobookItem) {
        if let i = audiobooks.firstIndex(where: { $0.id == book.id }) {
            audiobooks[i] = book
        } else {
            audiobooks.append(book)
        }
    }

    /// Resolve tracks for a given playlist (preserving playlist order).
    func tracks(for playlist: Playlist) -> [MediaItem] {
        let lookup = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { lookup[$0] }
    }

    /// Evaluate a smart playlist against the current library.
    func tracks(for smart: SmartPlaylist) -> [MediaItem] {
        var filtered = allTracks.filter { smart.matches($0) }
        if let limitCount = smart.limitCount {
            filtered = Array(filtered.prefix(limitCount))
        }
        return filtered
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private func rebuildGroupedViews() {
        // Sort raw tracks
        allTracks.sort(by: MediaItem.libraryOrder)

        // Build album groups
        var albumDict: [String: AlbumGroup] = [:]
        for track in allTracks {
            let albumKey = "\(track.album ?? "")::::\(track.albumArtist ?? track.artist ?? "")"
            if albumDict[albumKey] == nil {
                albumDict[albumKey] = AlbumGroup(
                    id: albumKey,
                    title: track.album ?? "Unknown Album",
                    artist: track.albumArtist ?? track.artist ?? "Unknown Artist",
                    year: track.year,
                    tracks: [],
                    artworkItemID: nil
                )
            }
            albumDict[albumKey]?.tracks.append(track)
        }
        albumGroups = albumDict.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        // Build artist groups from album groups
        var artistDict: [String: ArtistGroup] = [:]
        for album in albumGroups {
            let artistKey = album.artist
            if artistDict[artistKey] == nil {
                artistDict[artistKey] = ArtistGroup(id: artistKey, name: artistKey, albums: [])
            }
            artistDict[artistKey]?.albums.append(album)
        }
        artistGroups = artistDict.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
