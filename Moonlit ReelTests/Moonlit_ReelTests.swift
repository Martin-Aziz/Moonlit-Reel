// Moonlit_ReelTests.swift — Swift unit test suite
//
// Tests player state machine, smart playlist rules, and audiobook progress.

import XCTest
@testable import Moonlit_Reel

final class PlayerStateTests: XCTestCase {

    // MARK: - Queue Management

    func testReplaceQueueSetsCurrentItem() {
        let state = PlayerState()
        let items = [makeTrack("1"), makeTrack("2"), makeTrack("3")]
        state.replaceQueue(items, startAt: 1)
        XCTAssertEqual(state.currentItem?.id, "2")
        XCTAssertEqual(state.queueIndex, 1)
    }

    func testInsertNextAddsAfterCurrentIndex() {
        let state = PlayerState()
        state.replaceQueue([makeTrack("a"), makeTrack("b")])
        state.queueIndex = 0
        state.insertNext(makeTrack("x"))
        XCTAssertEqual(state.queue[1].id, "x", "Inserted item should be at index 1")
    }

    func testRemoveFromQueueAdjustsIndex() {
        let state = PlayerState()
        state.replaceQueue([makeTrack("0"), makeTrack("1"), makeTrack("2")])
        state.queueIndex = 2
        state.removeFromQueue(at: IndexSet(integer: 0))
        XCTAssertEqual(state.queueIndex, 1, "current index should shift down by 1")
    }

    // MARK: - Progress

    func testProgressFractionClamped() {
        let state = PlayerState()
        state.replaceQueue([makeTrack("t")])
        // Simulate position beyond duration (shouldn't happen but should be safe)
        state.positionSeconds = 999
        let item = makeTrack("t", duration: 300)
        state.currentItem = item
        XCTAssertLessThanOrEqual(state.progressFraction, 1.0)
    }

    // MARK: - Repeat Mode

    func testHasNextFalseWhenQueueEmptyAndRepeatOff() {
        let state = PlayerState()
        state.repeatMode = .off
        XCTAssertFalse(state.hasNext)
    }

    func testHasNextTrueWhenRepeatAll() {
        let state = PlayerState()
        state.repeatMode = .all
        state.replaceQueue([makeTrack("a")])
        XCTAssertTrue(state.hasNext)
    }

    // MARK: - Helpers

    func makeTrack(_ id: String, duration: Double = 300) -> MediaItem {
        MediaItem(
            id: id,
            url: URL(fileURLWithPath: "/music/\(id).mp3"),
            type_: .audio,
            title: "Track \(id)",
            artist: nil, albumArtist: nil, album: nil, genre: nil,
            year: nil, trackNumber: nil, discNumber: nil,
            composer: nil, comment: nil, bpm: nil,
            durationSeconds: duration,
            sampleRate: nil, bitRate: nil, channelCount: nil, codec: nil,
            fileSizeBytes: 0, modifiedAt: Date(),
            replayGainTrackDB: nil, replayGainAlbumDB: nil
        )
    }
}

// MARK: - SmartPlaylist Tests

final class SmartPlaylistTests: XCTestCase {

    func testArtistContainsRule() {
        var playlist = SmartPlaylist(name: "Test")
        playlist.rules = [SmartRule(
            field: .artist,
            op: .contains,
            value: .text("Radiohead")
        )]

        XCTAssertTrue(playlist.matches(makeTrackWith(artist: "Radiohead")))
        XCTAssertFalse(playlist.matches(makeTrackWith(artist: "Pink Floyd")))
    }

    func testYearGreaterThanRule() {
        var playlist = SmartPlaylist(name: "Test")
        playlist.rules = [SmartRule(
            field: .year,
            op: .greaterThan,
            value: .integer(1999)
        )]

        XCTAssertTrue(playlist.matches(makeTrackWith(year: 2000)))
        XCTAssertFalse(playlist.matches(makeTrackWith(year: 1995)))
    }

    func testOrConjunctionMatchesAny() {
        var playlist = SmartPlaylist(name: "Test")
        playlist.conjunction = .any
        playlist.rules = [
            SmartRule(field: .artist, op: .equals, value: .text("Artist A")),
            SmartRule(field: .artist, op: .equals, value: .text("Artist B"))
        ]

        XCTAssertTrue(playlist.matches(makeTrackWith(artist: "Artist A")))
        XCTAssertTrue(playlist.matches(makeTrackWith(artist: "Artist B")))
        XCTAssertFalse(playlist.matches(makeTrackWith(artist: "Artist C")))
    }

    func testDurationLessThanRule() {
        var playlist = SmartPlaylist(name: "Test")
        playlist.rules = [SmartRule(
            field: .durationSeconds,
            op: .lessThan,
            value: .decimal(200)
        )]

        XCTAssertTrue(playlist.matches(makeTrackWith(duration: 180)))
        XCTAssertFalse(playlist.matches(makeTrackWith(duration: 300)))
    }

    // MARK: - Helpers

    func makeTrackWith(
        artist: String = "Unknown", year: Int = 2000, duration: Double = 250
    ) -> MediaItem {
        MediaItem(
            id: UUID().uuidString,
            url: URL(fileURLWithPath: "/music/track.mp3"),
            type_: .audio,
            title: "Test Track",
            artist: artist, albumArtist: nil, album: "Album", genre: "Rock",
            year: year, trackNumber: nil, discNumber: nil,
            composer: nil, comment: nil, bpm: nil,
            durationSeconds: duration,
            sampleRate: nil, bitRate: nil, channelCount: nil, codec: nil,
            fileSizeBytes: 0, modifiedAt: Date(),
            replayGainTrackDB: nil, replayGainAlbumDB: nil
        )
    }
}

// MARK: - AudiobookItem Tests

final class AudiobookItemTests: XCTestCase {

    func testProgressFractionZeroWhenNothingPlayed() {
        let book = makeBook(totalDuration: 3600, resumeChapter: 0, resumePosition: 0)
        XCTAssertEqual(book.progressFraction, 0, accuracy: 0.001)
    }

    func testProgressFractionHalfway() {
        let book = makeBook(totalDuration: 1200, resumeChapter: 1, resumePosition: 300)
        // Chapter 0: 600s, Chapter 1: 300s position = 900s elapsed / 1200s total = 0.75
        XCTAssertEqual(book.progressFraction, 0.75, accuracy: 0.001)
    }

    func testRemainingSeconds() {
        let book = makeBook(totalDuration: 1200, resumeChapter: 0, resumePosition: 300)
        XCTAssertEqual(book.remainingSeconds, 900, accuracy: 0.001)
    }

    // MARK: - Helpers

    func makeBook(totalDuration: Double, resumeChapter: Int, resumePosition: Double) -> AudiobookItem {
        let chapters = [
            AudiobookChapter(index: 0, title: "Ch1", startSeconds: 0, endSeconds: 600,
                             fileURL: URL(fileURLWithPath: "/book/01.mp3")),
            AudiobookChapter(index: 1, title: "Ch2", startSeconds: 0, endSeconds: 600,
                             fileURL: URL(fileURLWithPath: "/book/02.mp3")),
        ]
        var book = AudiobookItem(
            id: "test-id",
            title: "Test Book", author: "Author", narrator: nil,
            folderURL: URL(fileURLWithPath: "/book"),
            chapters: chapters, totalDurationSeconds: totalDuration,
            artworkData: nil
        )
        book.resumeChapterIndex = resumeChapter
        book.resumePositionSeconds = resumePosition
        return book
    }
}

// MARK: - SearchService Tests

@MainActor
final class SearchServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "search.recentQueries.v1")
        UserDefaults.standard.removeObject(forKey: "search.savedQueries.v1")
    }

    func testExactMatchRanksAboveFuzzyNeighbor() async {
        let state = LibraryState()
        state.upsert(makeTrack(id: "exact", title: "Comfortably Numb", artist: "Pink Floyd"))
        state.upsert(makeTrack(id: "near", title: "Comfortable Numbers", artist: "Other Artist"))

        let service = SearchService(libraryState: state)
        service.search("Comfortably Numb")
        try? await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(service.results.first?.item.id, "exact")
    }

    func testQualifiedArtistQueryFiltersResults() async {
        let state = LibraryState()
        state.upsert(makeTrack(id: "r1", title: "Karma Police", artist: "Radiohead"))
        state.upsert(makeTrack(id: "p1", title: "Time", artist: "Pink Floyd"))

        let service = SearchService(libraryState: state)
        service.search("artist:radiohead")
        try? await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(service.results.count, 1)
        XCTAssertEqual(service.results.first?.item.id, "r1")
    }

    func testRecentAndSavedQueriesLifecycle() async {
        let state = LibraryState()
        state.upsert(makeTrack(id: "a", title: "Everything In Its Right Place", artist: "Radiohead"))

        let service = SearchService(libraryState: state)
        service.search("  radiohead   ")
        try? await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(service.recentQueries.first, "radiohead")

        service.saveCurrentQuery()
        XCTAssertEqual(service.savedQueries.first, "radiohead")

        service.removeSavedQuery("radiohead")
        XCTAssertTrue(service.savedQueries.isEmpty)
    }

    private func makeTrack(id: String, title: String, artist: String) -> MediaItem {
        MediaItem(
            id: id,
            url: URL(fileURLWithPath: "/music/\(id).mp3"),
            type_: .audio,
            title: title,
            artist: artist,
            albumArtist: nil,
            album: "Album",
            genre: "Rock",
            year: 2000,
            trackNumber: nil,
            discNumber: nil,
            composer: nil,
            comment: nil,
            bpm: nil,
            durationSeconds: 240,
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
}
