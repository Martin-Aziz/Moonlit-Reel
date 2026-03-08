// AudiobookViews.swift — Audiobook library and player views
//
// PURPOSE: Library grid of audiobooks, chapter-aware player view, chapter list,
//          sleep timer, and bookmark management.
// LAYER:   Presentation

import SwiftUI

// MARK: - Audiobook Library

struct AudiobookLibraryView: View {
    @Environment(\.libraryService)   var libraryService
    @Environment(\.audiobookService) var audiobookService

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200))]

    var body: some View {
        Group {
            if libraryService.state.audiobooks.isEmpty {
                emptyState
            } else {
                audiobookGrid
            }
        }
        .navigationTitle("Audiobooks")
        .navigationSubtitle("\(libraryService.state.audiobookCount) books")
    }

    private var audiobookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(libraryService.state.audiobooks) { book in
                    NavigationLink(value: book) {
                        AudiobookCardView(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationDestination(for: AudiobookItem.self) { book in
            AudiobookPlayerView(book: book)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Audiobooks", systemImage: "book.fill")
        } description: {
            Text("Add a folder with audiobook files (M4B or multi-file) to your library.")
        } actions: {
            Button("Add Folder") {
                Task { await libraryService.addFolderInteractively() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - AudiobookCard

private struct AudiobookCardView: View {
    let book: AudiobookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover art
            artworkView
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 5, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .font(.callout)
                Text(book.author)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .font(.caption)

                // Progress bar
                ProgressView(value: book.progressFraction)
                    .progressViewStyle(.linear)

                Text("\(book.formattedRemaining) remaining")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let data = book.artworkData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }
}

// MARK: - Audiobook Player View

struct AudiobookPlayerView: View {
    let book: AudiobookItem

    @Environment(\.audiobookService) var audiobookService
    @Environment(\.playerService)    var playerService

    @State private var showChapters = true
    @State private var showBookmarks = false
    @State private var showSleepTimer = false
    @State private var showAddBookmark = false
    @State private var bookmarkLabel = ""

    private var state: PlayerState { playerService.state }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: player ──────────────────────────────────────────────────
            playerPanel

            Divider()

            // ── Right: chapter list or bookmarks ──────────────────────────────
            if showChapters || showBookmarks {
                sidePanel
                    .frame(width: 260)
            }
        }
        .navigationTitle(book.title)
        .toolbar { toolbarItems }
        .onAppear {
            audiobookService.currentBook = book
        }
    }

    // MARK: - Player Panel

    private var playerPanel: some View {
        VStack(spacing: 24) {
            Spacer()

            // Cover art
            audiobookArtwork
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 16, y: 8)

            // Metadata
            VStack(spacing: 6) {
                Text(audiobookService.currentBook?.resumeChapter?.title ?? book.chapters.first?.title ?? book.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(book.title)
                    .foregroundStyle(.secondary)

                Text(book.author)
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
            .padding(.horizontal, 40)

            // Overall progress
            VStack(spacing: 4) {
                ProgressView(value: book.progressFraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text(formatTime(book.elapsedSeconds))
                    Spacer()
                    Text(book.formattedTotalDuration)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, 40)

            // Chapter progress scrubber
            PlayerScrubber(
                position: Binding(
                    get: { state.positionSeconds },
                    set: { playerService.state.positionSeconds = $0 }
                ),
                duration: state.currentDuration,
                onSeek: playerService.seek(to:)
            )
            .padding(.horizontal, 40)

            // Controls
            audiobookControls

            // Speed picker
            speedControl

            Spacer()
        }
        .frame(maxWidth: 440)
        .padding(.horizontal)
    }

    private var audiobookArtwork: some View {
        Group {
            if let data = book.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }

    private var audiobookControls: some View {
        HStack(spacing: 28) {
            Button(action: { audiobookService.previousChapter() }) {
                Image(systemName: "backward.end.fill").font(.title3)
            }
            .buttonStyle(.plain)

            Button(action: { audiobookService.skipBackward(30) }) {
                Image(systemName: "gobackward.30").font(.title2)
            }
            .buttonStyle(.plain)

            Button(action: playerService.togglePlayPause) {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .symbolEffect(.bounce, value: state.isPlaying)
            }
            .buttonStyle(.plain)

            Button(action: { audiobookService.skipForward(30) }) {
                Image(systemName: "goforward.30").font(.title2)
            }
            .buttonStyle(.plain)

            Button(action: { audiobookService.nextChapter() }) {
                Image(systemName: "forward.end.fill").font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    private var speedControl: some View {
        let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        return HStack(spacing: 6) {
            ForEach(speeds, id: \.self) { speed in
                Button("\(speed, specifier: speed == 1.0 ? "%.0f" : "%.2g")×") {
                    audiobookService.setSpeed(speed)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(audiobookService.playbackRate == speed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .controlSize(.mini)
            }
        }
    }

    // MARK: - Side Panel

    private var sidePanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { showBookmarks },
                set: { showBookmarks = $0; showChapters = !$0 }
            )) {
                Text("Chapters").tag(false)
                Text("Bookmarks").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            if showBookmarks {
                BookmarkListView(book: book)
            } else {
                ChapterListView(book: book)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { audiobookService.addBookmark() }) {
                Image(systemName: "bookmark.fill")
            }
            .help("Add Bookmark")

            Menu {
                ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        audiobookService.setSleepTimer(minutes: minutes)
                    }
                }
                if audiobookService.sleepTimer.isActive {
                    Divider()
                    Button("Cancel Timer") { audiobookService.cancelSleepTimer() }
                }
            } label: {
                Image(systemName: audiobookService.sleepTimer.isActive
                    ? "moon.zzz.fill" : "moon.zzz")
                    .foregroundStyle(audiobookService.sleepTimer.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .help("Sleep Timer")

            Button(action: { showChapters.toggle() }) {
                Image(systemName: "list.bullet.indent")
            }
            .help("Toggle Chapters")
        }
    }
}

// MARK: - Chapter List

struct ChapterListView: View {
    let book: AudiobookItem
    @Environment(\.audiobookService) var audiobookService

    var body: some View {
        List(book.chapters) { chapter in
            ChapterRowView(chapter: chapter, isCurrent: audiobookService.currentBook?.resumeChapterIndex == chapter.index)
                .onTapGesture(count: 2) {
                    audiobookService.play(book: book, chapterIndex: chapter.index)
                }
        }
        .listStyle(.plain)
    }
}

private struct ChapterRowView: View {
    let chapter: AudiobookChapter
    let isCurrent: Bool

    var body: some View {
        HStack {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(width: 14)
            } else {
                Text("\(chapter.index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                Text(chapter.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Bookmark List

struct BookmarkListView: View {
    let book: AudiobookItem
    @Environment(\.audiobookService) var audiobookService

    var body: some View {
        List {
            if book.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                    description: Text("Tap the bookmark button to save your position."))
            } else {
                ForEach(book.bookmarks) { bookmark in
                    BookmarkRowView(bookmark: bookmark)
                        .onTapGesture(count: 2) {
                            audiobookService.jumpToBookmark(bookmark)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                audiobookService.removeBookmark(id: bookmark.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct BookmarkRowView: View {
    let bookmark: AudiobookBookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bookmark.label)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack {
                Text("Ch. \(bookmark.chapterIndex + 1)")
                Text("·")
                Text(bookmark.formattedPosition)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Helpers

private func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    let m = s / 60
    let h = m / 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m % 60, s % 60) }
    return String(format: "%d:%02d", m % 60, s % 60)
}
