// Audiobook.swift — Audiobook domain model for Swift layer
//
// PURPOSE: Swift-side representation of audiobooks and chapters,
//          mirroring Rust `Audiobook` / `Chapter` structs.
// LAYER:   Domain Model

import Foundation

/// A single chapter within an audiobook.
struct AudiobookChapter: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var index: Int
    var title: String
    var startSeconds: Double
    var endSeconds: Double
    var fileURL: URL

    init(index: Int, title: String, startSeconds: Double, endSeconds: Double, fileURL: URL) {
        self.id           = UUID()
        self.index        = index
        self.title        = title
        self.startSeconds = startSeconds
        self.endSeconds   = endSeconds
        self.fileURL      = fileURL
    }

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    var formattedDuration: String {
        Duration.seconds(durationSeconds).formatted(
            .time(pattern: durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }
}

/// A user-created position bookmark within an audiobook.
struct AudiobookBookmark: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var audiobookID: String
    var chapterIndex: Int
    var positionSeconds: Double
    var label: String
    var createdAt: Date

    init(audiobookID: String, chapterIndex: Int, positionSeconds: Double, label: String = "") {
        self.id              = UUID()
        self.audiobookID     = audiobookID
        self.chapterIndex    = chapterIndex
        self.positionSeconds = positionSeconds
        self.label           = label.isEmpty ? "Bookmark at \(formatSeconds(positionSeconds))" : label
        self.createdAt       = Date()
    }

    var formattedPosition: String { formatSeconds(positionSeconds) }
}

/// An audiobook: a folder or M4B file treated as a first-class entity.
struct AudiobookItem: Identifiable, Hashable, Codable, Sendable {
    // ── Identity ─────────────────────────────────────────────────────────────
    let id: String                /// Stable BLAKE3 of folder/file path
    var title: String
    var author: String
    var narrator: String?
    var folderURL: URL

    // ── Content ──────────────────────────────────────────────────────────────
    var chapters: [AudiobookChapter]
    var totalDurationSeconds: Double

    // ── Artwork ──────────────────────────────────────────────────────────────
    var artworkData: Data?

    // ── Progress ─────────────────────────────────────────────────────────────
    var resumeChapterIndex: Int = 0
    var resumePositionSeconds: Double = 0

    // ── Bookmarks ────────────────────────────────────────────────────────────
    var bookmarks: [AudiobookBookmark] = []

    // ── Derived ──────────────────────────────────────────────────────────────

    var progressFraction: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return (elapsedSeconds / totalDurationSeconds).clamped(0, 1)
    }

    var elapsedSeconds: Double {
        let completedChaptersDuration = chapters
            .prefix(resumeChapterIndex)
            .reduce(0) { $0 + $1.durationSeconds }
        return completedChaptersDuration + resumePositionSeconds
    }

    var remainingSeconds: Double {
        max(0, totalDurationSeconds - elapsedSeconds)
    }

    var resumeChapter: AudiobookChapter? {
        guard chapters.indices.contains(resumeChapterIndex) else { return nil }
        return chapters[resumeChapterIndex]
    }

    /// The highest chapter index the user has started (chapters before this are "heard").
    var heardUpToChapterIndex: Int { resumeChapterIndex }

    enum ChapterListenState {
        case heard, current, unheard
    }

    func listenState(for chapter: AudiobookChapter) -> ChapterListenState {
        if chapter.index < resumeChapterIndex { return .heard }
        if chapter.index == resumeChapterIndex { return .current }
        return .unheard
    }

    var formattedTotalDuration: String {
        Duration.seconds(totalDurationSeconds).formatted(
            .time(pattern: totalDurationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    var formattedRemaining: String {
        Duration.seconds(remainingSeconds).formatted(
            .time(pattern: remainingSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    // ── Hashable ─────────────────────────────────────────────────────────────
    static func == (lhs: AudiobookItem, rhs: AudiobookItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Sleep Timer

/// Controls a sleep-timer that fades then stops playback after a duration.
struct SleepTimer: Codable, Sendable {
    var endDate: Date?
    var fadeDurationSeconds: Double = 5.0

    var isActive: Bool { endDate != nil }

    var remainingSeconds: Double {
        guard let end = endDate else { return 0 }
        return max(0, end.timeIntervalSinceNow)
    }

    mutating func set(minutes: Int) {
        endDate = Date().addingTimeInterval(Double(minutes) * 60)
    }

    mutating func cancel() {
        endDate = nil
    }
}

// MARK: - Formatting helper

private func formatSeconds(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
