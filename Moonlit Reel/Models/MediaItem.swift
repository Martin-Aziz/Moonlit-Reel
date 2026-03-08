// MediaItem.swift — Core domain entity for all media files
//
// PURPOSE: Unified value type representing any media item (audio, video,
//          audiobook chapter) in the library. Mirrors TrackMetadata from Rust.
// LAYER:   Domain Model

import Foundation

/// The kind of media file a `MediaItem` represents.
enum MediaItemType: String, Codable, CaseIterable, Identifiable {
    case audio
    case video
    case audiobookChapter

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .audio:            return "music.note"
        case .video:            return "film"
        case .audiobookChapter: return "book.fill"
        }
    }
}

/// All metadata and technical properties for a single media file.
///
/// Immutable value type. Services produce new instances when metadata
/// changes; SwiftUI diffs are efficient because `id` is stable.
struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    // ── Identity ─────────────────────────────────────────────────────────────
    /// Stable BLAKE3 hash of the canonical file path (from Rust engine).
    let id: String
    let url: URL

    // ── Categorization ───────────────────────────────────────────────────────
    let type_: MediaItemType

    // ── Tags ─────────────────────────────────────────────────────────────────
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var composer: String?
    var comment: String?
    var bpm: Int?

    // ── Technical ────────────────────────────────────────────────────────────
    var durationSeconds: Double
    var sampleRate: Int?
    var bitRate: Int?
    var channelCount: Int?
    var codec: String?

    // ── Filesystem ───────────────────────────────────────────────────────────
    var fileSizeBytes: Int
    var modifiedAt: Date

    // ── ReplayGain ───────────────────────────────────────────────────────────
    var replayGainTrackDB: Double?
    var replayGainAlbumDB: Double?

    // ── Derived display properties ───────────────────────────────────────────

    /// Display title: tag title if present, otherwise filename stem.
    nonisolated var displayTitle: String {
        title ?? url.deletingPathExtension().lastPathComponent
    }

    nonisolated var displayArtist: String {
        artist ?? albumArtist ?? "Unknown Artist"
    }

    var displayAlbum: String {
        album ?? "Unknown Album"
    }

    var formattedDuration: String {
        Duration.seconds(durationSeconds).formatted(
            .time(pattern: durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    /// Audio-only check (not video or audiobook).
    var isAudio: Bool { type_ == .audio || type_ == .audiobookChapter }

    // ── Hashable / Equatable ─────────────────────────────────────────────────
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Sorting helpers

extension MediaItem {
    /// Comparator for default library sort: album artist → album → disc → track.
    nonisolated static func libraryOrder(_ a: MediaItem, _ b: MediaItem) -> Bool {
        let aa = a.albumArtist ?? a.artist ?? ""
        let ba = b.albumArtist ?? b.artist ?? ""
        if aa != ba { return aa.localizedCaseInsensitiveCompare(ba) == .orderedAscending }
        let al = a.album ?? ""
        let bl = b.album ?? ""
        if al != bl { return al.localizedCaseInsensitiveCompare(bl) == .orderedAscending }
        let ad = a.discNumber ?? 0
        let bd = b.discNumber ?? 0
        if ad != bd { return ad < bd }
        return (a.trackNumber ?? 0) < (b.trackNumber ?? 0)
    }
}
