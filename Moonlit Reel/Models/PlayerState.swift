// PlayerState.swift — Observable playback state machine
//
// PURPOSE: Single source of truth for all player state accessible from SwiftUI.
//          Owned by PlayerService; published to views via @Observable.
// LAYER:   Domain (pure state; no I/O)

import Foundation
import Combine

/// Transport state of the media player.
enum PlaybackStatus: Equatable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(String)
}

/// Active repeat mode.
enum RepeatMode: String, CaseIterable, Identifiable {
    case off
    case one   = "Repeat One"
    case all   = "Repeat All"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

/// Complete snapshot of current player state.
///
/// This is a value type passed around for UI rendering;
/// `PlayerService` is the `@Observable` that owns it.
@Observable
final class PlayerState {
    // ── Currently playing ────────────────────────────────────────────────────
    var currentItem: MediaItem?
    var queue: [MediaItem] = []
    var queueIndex: Int = 0

    // ── Transport ────────────────────────────────────────────────────────────
    var status: PlaybackStatus = .idle
    var positionSeconds: Double = 0
    var bufferedSeconds: Double = 0

    // ── Controls ─────────────────────────────────────────────────────────────
    var volume: Float = 1.0          /// 0.0–1.0
    var isMuted: Bool = false
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false
    var playbackRate: Double = 1.0   /// 0.5–2.0

    // ── Effects ──────────────────────────────────────────────────────────────
    var isEqEnabled: Bool = false
    var crossfadeDuration: Double = 0   /// seconds
    var isReplayGainEnabled: Bool = false
    var useAlbumGain: Bool = true

    // ── Derived ──────────────────────────────────────────────────────────────

    var isPlaying: Bool { status == .playing }

    var currentDuration: Double {
        currentItem?.durationSeconds ?? 0
    }

    var progressFraction: Double {
        currentDuration > 0 ? (positionSeconds / currentDuration).clamped(0, 1) : 0
    }

    var hasNext: Bool {
        switch repeatMode {
        case .all: return !queue.isEmpty
        case .one: return true
        case .off: return queueIndex + 1 < queue.count
        }
    }

    var hasPrevious: Bool {
        queueIndex > 0 || positionSeconds > 3
    }

    var nextItem: MediaItem? {
        guard !queue.isEmpty else { return nil }
        let nextIndex = queueIndex + 1
        return nextIndex < queue.count ? queue[nextIndex] : (repeatMode == .all ? queue.first : nil)
    }

    var previousItem: MediaItem? {
        guard queueIndex > 0 else { return nil }
        return queue[queueIndex - 1]
    }

    // ── Queue management ─────────────────────────────────────────────────────

    func replaceQueue(_ items: [MediaItem], startAt index: Int = 0) {
        queue = items
        queueIndex = index.clamped(0, max(0, items.count - 1))
        currentItem = items.isEmpty ? nil : items[index]
    }

    func insertNext(_ item: MediaItem) {
        let insertAt = min(queueIndex + 1, queue.count)
        queue.insert(item, at: insertAt)
    }

    func appendToQueue(_ item: MediaItem) {
        queue.append(item)
    }

    func removeFromQueue(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        // Adjust current index if needed
        if let first = offsets.first, first <= queueIndex {
            queueIndex = max(0, queueIndex - 1)
        }
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(_ lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}
