// AudiobookService.swift — Audiobook detection, progress persistence, sleep timer
//
// PURPOSE: Detects audiobook folders/M4B files, manages chapter-aware playback,
//          persists resume positions per-chapter, and drives the sleep timer.
// LAYER:   Application Service
// DEPENDS ON: PlayerService, LibraryState, AudiobookItem

import Foundation

@MainActor
@Observable
final class AudiobookService {

    // ── Public state ─────────────────────────────────────────────────────────
    var currentBook: AudiobookItem?
    var sleepTimer: SleepTimer = SleepTimer()
    var playbackRate: Double = 1.0  // Audiobook-specific speed (default 1x)

    // ── Dependencies ─────────────────────────────────────────────────────────
    private let playerService: PlayerService
    private let libraryState: LibraryState
    private var sleepTimerTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?

    // ── Persistence ───────────────────────────────────────────────────────────
    private let defaults = UserDefaults.standard
    private func resumeKey(_ bookID: String) -> String { "audiobook.resume.\(bookID)" }
    private func chapterKey(_ bookID: String) -> String { "audiobook.chapter.\(bookID)" }

    init(playerService: PlayerService, libraryState: LibraryState) {
        self.playerService = playerService
        self.libraryState  = libraryState

        autoSaveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await MainActor.run {
                    self.saveCurrentPosition()
                }
            }
        }
    }

    // MARK: - Detection

    /// Attempt to detect and register an audiobook from a folder or M4B URL.
    ///
    /// - Returns: The detected `AudiobookItem`, or `nil` if not an audiobook.
    func detectAudiobook(at url: URL) async -> AudiobookItem? {
        if url.pathExtension.lowercased() == "m4b" {
            return await buildAudiobookFromM4B(url: url)
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let audioFiles = contents.filter { isSupportedAudioFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard audioFiles.count >= 2 else { return nil }

        return buildAudiobookFromFiles(audioFiles, folderURL: url)
    }

    // MARK: - Playback

    /// Start or resume an audiobook from the last saved position.
    func play(_ book: AudiobookItem) {
        currentBook = book
        let chapterIndex = savedChapterIndex(book)
        let position     = savedPosition(book)
        if position > 0 || chapterIndex > 0 {
            PlaybackInsightsStore.recordEvent(.audiobookResumed, metadata: [
                "bookID": book.id,
                "chapterIndex": "\(chapterIndex)",
                "positionSeconds": "\(Int(position))"
            ])
        }
        play(book: book, chapterIndex: chapterIndex, startAt: position)
    }

    /// Jump to a specific chapter.
    func play(book: AudiobookItem, chapterIndex: Int, startAt positionSeconds: Double = 0) {
        guard book.chapters.indices.contains(chapterIndex) else { return }
        var mutable = book
        mutable.resumeChapterIndex = chapterIndex
        mutable.resumePositionSeconds = max(0, positionSeconds)
        currentBook = mutable

        // Build a queue: current chapter first, then remaining chapters as MediaItems
        let remainingChapters = mutable.chapters[chapterIndex...]
        let queue = remainingChapters.map { chapter in
            makeMediaItem(from: chapter, book: mutable)
        }

        playerService.play(queue: queue, startAt: 0)
        playerService.setPlaybackRate(playbackRate)

        if positionSeconds > 0 {
            Task {
                // Small delay to let AVAudioFile load before seeking
                try? await Task.sleep(for: .milliseconds(300))
                playerService.seek(to: positionSeconds)
            }
        }
    }

    /// Skip forward by `seconds` (audiobook-aware: may cross chapter boundaries).
    func skipForward(_ seconds: Double = 30) {
        playerService.skipForward(seconds: seconds)
    }

    func skipBackward(_ seconds: Double = 30) {
        let position = playerService.state.positionSeconds
        if position > seconds {
            playerService.skipBackward(seconds: seconds)
        } else if let book = currentBook {
            // Jump to end of previous chapter
            let prevIdx = max(0, (currentBook?.resumeChapterIndex ?? 0) - 1)
            play(book: book, chapterIndex: prevIdx)
        }
    }

    func nextChapter() {
        guard let book = currentBook else { return }
        let next = (book.resumeChapterIndex + 1)
        play(book: book, chapterIndex: min(next, book.chapters.count - 1))
    }

    func previousChapter() {
        guard let book = currentBook else { return }
        let prev = max(0, book.resumeChapterIndex - 1)
        play(book: book, chapterIndex: prev)
    }

    // MARK: - Sleep Timer

    /// Set a sleep timer that stops playback after `minutes`.
    func setSleepTimer(minutes: Int) {
        sleepTimer.set(minutes: minutes)
        sleepTimerTask?.cancel()
        sleepTimerTask = Task {
            let delay = Double(minutes) * 60 - sleepTimer.fadeDurationSeconds
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            await fadeAndStop()
        }
    }

    func cancelSleepTimer() {
        sleepTimer.cancel()
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
    }

    // MARK: - Bookmarks

    func addBookmark(label: String = "") {
        guard let book = currentBook else { return }
        let chapterIdx = book.resumeChapterIndex
        let position   = playerService.state.positionSeconds
        let bookmark   = AudiobookBookmark(
            audiobookID: book.id,
            chapterIndex: chapterIdx,
            positionSeconds: position,
            label: label
        )
        var updated = book
        updated.bookmarks.append(bookmark)
        currentBook = updated
        libraryState.upsertAudiobook(updated)
    }

    func removeBookmark(id: UUID) {
        guard var book = currentBook else { return }
        book.bookmarks.removeAll { $0.id == id }
        currentBook = book
        libraryState.upsertAudiobook(book)
    }

    func jumpToBookmark(_ bookmark: AudiobookBookmark) {
        guard let book = currentBook else { return }
        play(book: book, chapterIndex: bookmark.chapterIndex, startAt: bookmark.positionSeconds)
    }

    // MARK: - Resume Persistence

    func saveCurrentPosition() {
        guard let book = currentBook else { return }
        let position = playerService.state.positionSeconds
        defaults.set(position, forKey: resumeKey(book.id))
        defaults.set(book.resumeChapterIndex, forKey: chapterKey(book.id))

        PlaybackInsightsStore.recordProgress(
            itemID: book.id,
            positionSeconds: position,
            durationSeconds: book.totalDurationSeconds
        )

        var updated = book
        updated.resumePositionSeconds = position
        currentBook = updated
        libraryState.upsertAudiobook(updated)
    }

    private func savedPosition(_ book: AudiobookItem) -> Double {
        defaults.double(forKey: resumeKey(book.id))
    }

    private func savedChapterIndex(_ book: AudiobookItem) -> Int {
        defaults.integer(forKey: chapterKey(book.id))
    }

    // MARK: - Playback speed

    func setSpeed(_ rate: Double) {
        playbackRate = rate.clamped(0.5, 2.5)
        playerService.setPlaybackRate(playbackRate)
    }

    // MARK: - Private

    private func buildAudiobookFromM4B(url: URL) async -> AudiobookItem? {
        let metadata = try? await MetadataService().parse(url: url)
        let durationSecs = metadata?.durationSeconds ?? 0

        let id = sha256Hex(url.standardizedFileURL.path)
        let chapter = AudiobookChapter(
            index: 0,
            title: metadata?.displayTitle ?? url.deletingPathExtension().lastPathComponent,
            startSeconds: 0,
            endSeconds: durationSecs,
            fileURL: url
        )

        return AudiobookItem(
            id: id,
            title: metadata?.displayTitle ?? url.deletingPathExtension().lastPathComponent,
            author: metadata?.artist ?? "",
            narrator: nil,
            folderURL: url.deletingLastPathComponent(),
            chapters: [chapter],
            totalDurationSeconds: durationSecs,
            artworkData: nil
        )
    }

    private func buildAudiobookFromFiles(_ files: [URL], folderURL: URL) -> AudiobookItem {
        let title = folderURL.lastPathComponent
        let id = sha256Hex(folderURL.standardizedFileURL.path)

        let chapters = files.enumerated().map { i, url in
            AudiobookChapter(
                index: i,
                title: url.deletingPathExtension().lastPathComponent,
                startSeconds: 0,
                endSeconds: 0,  // Updated after metadata parse
                fileURL: url
            )
        }

        return AudiobookItem(
            id: id,
            title: title,
            author: "",
            narrator: nil,
            folderURL: folderURL,
            chapters: chapters,
            totalDurationSeconds: 0,
            artworkData: nil
        )
    }

    private func makeMediaItem(from chapter: AudiobookChapter, book: AudiobookItem) -> MediaItem {
        MediaItem(
            id: sha256Hex(chapter.fileURL.standardizedFileURL.path),
            url: chapter.fileURL,
            type_: .audiobookChapter,
            title: chapter.title,
            artist: book.author,
            albumArtist: book.author,
            album: book.title,
            genre: "Audiobook",
            year: nil,
            trackNumber: chapter.index + 1,
            discNumber: nil,
            composer: nil,
            comment: nil,
            bpm: nil,
            durationSeconds: chapter.durationSeconds,
            sampleRate: nil,
            bitRate: nil,
            channelCount: nil,
            codec: nil,
            fileSizeBytes: 0,
            modifiedAt: Date(),
            replayGainTrackDB: nil,
            replayGainAlbumDB: nil
        )
    }

    private func isSupportedAudioFile(_ url: URL) -> Bool {
        let audio: Set<String> = ["mp3", "m4a", "m4b", "aac", "flac", "ogg", "opus", "wav"]
        return audio.contains(url.pathExtension.lowercased())
    }

    private func fadeAndStop() async {
        let steps = 20
        let initialVolume = playerService.state.volume
        let stepDuration  = sleepTimer.fadeDurationSeconds / Double(steps)
        for step in 0..<steps {
            try? await Task.sleep(for: .seconds(stepDuration))
            let factor = 1.0 - Float(step + 1) / Float(steps)
            playerService.setVolume(initialVolume * factor)
        }
        playerService.pause()
        playerService.setVolume(initialVolume)
        sleepTimer.cancel()
    }
}

import CryptoKit

private func sha256Hex(_ s: String) -> String {
    let data = Data(s.utf8)
    return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
