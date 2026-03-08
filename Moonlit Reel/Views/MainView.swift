// MainView.swift — Root application view with NavigationSplitView
//
// PURPOSE: Top-level navigation shell. Hosts sidebar, content area, and
//          persistent mini-player bar. Manages navigation state.
// LAYER:   Presentation

import SwiftUI

/// Navigation destination sections in the sidebar.
enum NavigationSection: String, CaseIterable, Identifiable, Hashable {
    case library      = "Library"
    case albums       = "Albums"
    case artists      = "Artists"
    case videos       = "Videos"
    case audiobooks   = "Audiobooks"
    case playlists    = "Playlists"
    case queue        = "Queue"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library:    return "music.note.list"
        case .albums:     return "square.grid.2x2"
        case .artists:    return "person.2"
        case .videos:     return "film.stack"
        case .audiobooks: return "book.fill"
        case .playlists:  return "list.bullet"
        case .queue:      return "list.number"
        }
    }
}

/// The root view wired to all app-level services via @Environment.
struct MainView: View {
    @Environment(\.playerService)    var playerService
    @Environment(\.libraryService)   var libraryService
    @Environment(\.audiobookService) var audiobookService
    @Environment(\.searchService)    var searchService

    @State private var selectedSection: NavigationSection? = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingFullscreenPlayer = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ── Sidebar ──────────────────────────────────────────────────────
            sidebar
        } detail: {
            // ── Content area ─────────────────────────────────────────────────
            contentArea
        }
        .toolbar { toolbarItems }
        .overlay(alignment: .bottom) {
            // ── Persistent mini-player ────────────────────────────────────────
            VStack(spacing: 0) {
                Divider()
                MiniPlayerView(isShowingFullscreen: $isShowingFullscreenPlayer)
                    .background(.bar)
            }
            .ignoresSafeArea(.keyboard)
        }
        .sheet(isPresented: $isShowingFullscreenPlayer) {
            FullscreenPlayerView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task {
            await libraryService.restoreFromBookmarks()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
        .navigationTitle("Moonlit Reel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await libraryService.addFolderInteractively() } }) {
                    Image(systemName: "plus")
                }
                .help("Add Folder to Library")
            }
        }
        .overlay {
            if libraryService.state.isScanning {
                scanProgressOverlay
            }
        }
    }

    private var scanProgressOverlay: some View {
        VStack(spacing: 6) {
            ProgressView(value: libraryService.state.scanProgress)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            Text("Scanning library…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .bottom)
        .background(.ultraThinMaterial)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedSection ?? .library {
        case .library:
            LibraryView()
        case .albums:
            AlbumGridView()
        case .artists:
            ArtistListView()
        case .videos:
            VideoLibraryView()
        case .audiobooks:
            AudiobookLibraryView()
        case .playlists:
            PlaylistSidebarView()
        case .queue:
            QueueView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

        ToolbarItem(placement: .automatic) {
            SearchBar(searchService: searchService)
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { isShowingSettings = true }) {
                Image(systemName: "gear")
            }
            .help("Settings")
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .all ? .detailOnly : .all
        }
    }
}

// MARK: - Search Bar

private struct SearchBar: View {
    @Bindable var searchService: SearchService
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search library…", text: $searchService.query)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !searchService.query.isEmpty {
                Button(action: searchService.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Placeholder views for sections not yet implemented inline

private struct PlaylistSidebarView: View {
    var body: some View {
        ContentUnavailableView("Playlists", systemImage: "list.bullet",
            description: Text("Create playlists from the Library view."))
    }
}
