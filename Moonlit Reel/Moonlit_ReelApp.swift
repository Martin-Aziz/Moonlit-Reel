// Moonlit_ReelApp.swift — Application entry point
//
// PURPOSE: Bootstraps all services, injects them into the SwiftUI environment,
//          and configures the main window.
// LAYER:   Application Bootstrap

import SwiftUI

@main
struct MoonlitReelApp: App {
    // ── Service construction (done once at app launch) ────────────────────────
    @State private var playerService    = PlayerService()
    @State private var libraryService   = LibraryService()
    @State private var audiobookService: AudiobookService
    @State private var searchService:   SearchService
    @State private var themeService     = ThemeService()

    init() {
        let player  = PlayerService()
        let library = LibraryService()
        let search  = SearchService(libraryState: library.state)
        let audiobook = AudiobookService(playerService: player, libraryState: library.state)

        _playerService    = State(initialValue: player)
        _libraryService   = State(initialValue: library)
        _audiobookService = State(initialValue: audiobook)
        _searchService    = State(initialValue: search)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.playerService,    playerService)
                .environment(\.libraryService,   libraryService)
                .environment(\.audiobookService, audiobookService)
                .environment(\.searchService,    searchService)
                .environment(\.metadataService,  MetadataService())
                .environment(\.themeService,     themeService)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            MoonlitReelCommands(
                playerService: playerService,
                libraryService: libraryService
            )
        }

        // Mini player in a separate always-on-top floating window (optional)
        // Uncomment to enable detached mini-player window
        // Window("Mini Player", id: "mini-player") {
        //     MiniPlayerView(isShowingFullscreen: .constant(false))
        //         .environment(\.playerService, playerService)
        // }
        // .windowStyle(.hiddenTitleBar)
        // .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Commands

struct MoonlitReelCommands: Commands {
    let playerService: PlayerService
    let libraryService: LibraryService

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") { playerService.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") { playerService.playNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") { playerService.playPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Skip Forward 15s") { playerService.skipForward(seconds: 15) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

            Button("Skip Backward 15s") { playerService.skipBackward(seconds: 15) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Divider()

            Button("Volume Up") { playerService.setVolume(min(1, playerService.state.volume + 0.05)) }
                .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") { playerService.setVolume(max(0, playerService.state.volume - 0.05)) }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }

        CommandMenu("Library") {
            Button("Add Folder to Library…") {
                Task { await libraryService.addFolderInteractively() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Rescan Library") {
                Task { await libraryService.rescanAll() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
