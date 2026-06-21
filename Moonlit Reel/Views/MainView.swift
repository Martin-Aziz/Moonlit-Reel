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
    @Environment(\.themeService)     var themeService
    @Environment(\.remoteService)    var remoteService

    @State private var selectedSection: NavigationSection? = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingFullscreenPlayer = false
    @State private var isShowingSettings = false
    @State private var isShowingScanReport = false
    @State private var showReadOnlyTrustModal = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            contentArea
        }
        .toolbar { toolbarItems }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Divider()
                    .foregroundColor(themeService.colors.dividerColor)
                MiniPlayerView(isShowingFullscreen: $isShowingFullscreenPlayer)
                    .background(themeService.gradients.miniPlayerGradient)
            }
            .ignoresSafeArea(.keyboard)
        }
        .background(themeService.gradients.backgroundGradient)
        .colorScheme(themeService.currentTheme.colorScheme)
        .sheet(isPresented: $isShowingFullscreenPlayer) {
            FullscreenPlayerView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingScanReport) {
            if let report = libraryService.state.latestScanReport {
                ScanReportSheet(report: report)
            }
        }
        .sheet(isPresented: $showReadOnlyTrustModal) {
            ReadOnlyTrustModal(isPresented: $showReadOnlyTrustModal)
        }
        .task {
            await libraryService.restoreFromBookmarks()
            remoteService.refreshFromSettings()
            searchService.updateFacets()
            // Show read-only trust modal on first ever launch
            let key = "hasSeenReadOnlyModal"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                showReadOnlyTrustModal = true
            }
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
        .safeAreaInset(edge: .top) {
            VStack(spacing: 12) {
                LogoWithText()
                // Read-only trust badge
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Read-only · never writes to files")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.tertiary, in: Capsule())
                Divider()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
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

    @ViewBuilder
    private var scanProgressOverlay: some View {
        let state = libraryService.state
        let indexed = state.scanIndexedCount
        let total = state.scanTotalCount
        let elapsed = state.scanStartedAt.map { -$0.timeIntervalSinceNow } ?? 0

        VStack(spacing: 6) {
            ProgressView(value: state.scanProgress)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            HStack {
                if total > 0 {
                    Text("\(indexed.formatted()) / \(total.formatted())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Scanning…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if elapsed >= 1 {
                    Text(String(format: "%.1fs", elapsed))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
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
            if let report = libraryService.state.latestScanReport, !libraryService.state.isScanning {
                Button(action: { isShowingScanReport = true }) {
                    Image(systemName: report.failedCount > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(report.failedCount > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .help("View Last Scan Report")
            }
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

// MARK: - Read-Only Trust Modal

struct ReadOnlyTrustModal: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Moonlit Reel reads your files.")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("It never writes to them.")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text("Your library is accessed in read-only mode. Moonlit Reel cannot modify, rename, move, or delete any file in your collection — ever.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Got it") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

// MARK: - Scan Report Sheet

struct ScanReportSheet: View {
    let report: LibraryScanReport
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Report")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(report.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Summary stats
            HStack(spacing: 0) {
                statCell(
                    value: "\(report.importedCount.formatted())",
                    label: "Imported",
                    color: .green
                )
                Divider().frame(height: 50)
                statCell(
                    value: "\(report.skippedUnsupportedCount.formatted())",
                    label: "Skipped",
                    color: .secondary
                )
                Divider().frame(height: 50)
                statCell(
                    value: "\(report.failedCount.formatted())",
                    label: "Errors",
                    color: report.failedCount > 0 ? .orange : .secondary
                )
                Divider().frame(height: 50)
                statCell(
                    value: String(format: "%.1fs", report.durationSeconds),
                    label: "Duration",
                    color: .secondary
                )
            }
            .padding(.vertical, 8)

            Divider()

            // No files modified notice
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tint)
                Text("No files were modified. Moonlit Reel is read-only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary)

            // Error list (if any)
            if !report.parseFailures.isEmpty {
                Divider()
                Text("Parse Failures")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)

                List(report.parseFailures) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: issue.filePath).lastPathComponent)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(issue.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("All files imported successfully.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
