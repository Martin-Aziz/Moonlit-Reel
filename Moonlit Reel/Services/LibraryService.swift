// LibraryService.swift — Library scanning, indexing, and persistence
//
// PURPOSE: Manages folder selection, parallel library scanning (via Rust FFI),
//          metadata persistence (via Rust sled), and incremental updates to LibraryState.
// LAYER:   Application Service
// DEPENDS ON: LibraryState, MediaItem, MetadataService
// SECURITY: Security-Scoped Bookmarks for App Sandbox file access

import Foundation
import AppKit

/// Encapsulates all library management operations.
///
/// Methods are `async` so they can be called from SwiftUI `Task` blocks.
/// The `libraryState` property is `@Observable` and safe to read on MainActor.
@MainActor
@Observable
final class LibraryService {

    // ── Published state ───────────────────────────────────────────────────────
    let state: LibraryState = LibraryState()

    // ── Private ───────────────────────────────────────────────────────────────
    private let metadataService: MetadataService
    private let persistenceKey = "library.rootBookmarks"
    private var activeScans: [URL: Task<Void, Never>] = [:]

    init(metadataService: MetadataService = MetadataService()) {
        self.metadataService = metadataService
    }

    // MARK: - Folder Management

    /// Present NSOpenPanel and add the selected folder to the library.
    func addFolderInteractively() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing your media files"
        panel.prompt = "Add to Library"

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        guard response == .OK, let url = panel.url else { return }

        await addFolder(url)
    }

    /// Add a folder URL to the library (creates Security-Scoped Bookmark + scans).
    func addFolder(_ url: URL) async {
        guard !state.libraryRootURLs.contains(url) else { return }

        // Persist security-scoped bookmark so we can access this folder after restart
        persistBookmark(for: url)
        state.libraryRootURLs.append(url)

        await scanFolder(url)
    }

    /// Remove a folder and all its tracks from the library.
    func removeFolder(_ url: URL) {
        state.libraryRootURLs.removeAll { $0 == url }
        activeScans[url]?.cancel()
        activeScans[url] = nil
        // Remove tracks whose path starts with this folder
        let prefix = url.path
        for track in state.allTracks where track.url.path.hasPrefix(prefix) {
            state.remove(id: track.id)
        }
    }

    // MARK: - Scanning

    /// Scan a single folder, updating `state` incrementally.
    func scanFolder(_ url: URL) async {
        // Cancel any in-progress scan on the same folder
        activeScans[url]?.cancel()

        let task = Task {
            state.isScanning = true
            defer { state.isScanning = false }

            guard url.startAccessingSecurityScopedResource() else {
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            await walkAndParse(folder: url)
            state.lastScanDate = Date()
        }

        activeScans[url] = task
        await task.value
    }

    /// Rescan all library roots.
    func rescanAll() async {
        for url in state.libraryRootURLs {
            await scanFolder(url)
        }
    }

    // MARK: - Startup Restoration

    /// Restore library roots from persisted Security-Scoped Bookmarks.
    func restoreFromBookmarks() async {
        guard let bookmarkDict = UserDefaults.standard.dictionary(forKey: persistenceKey)
            as? [String: Data] else { return }

        for (_, bookmarkData) in bookmarkDict {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if !state.libraryRootURLs.contains(url) {
                    state.libraryRootURLs.append(url)
                }
                if isStale {
                    persistBookmark(for: url)
                }
                await scanFolder(url)
            }
        }
    }

    // MARK: - Private helpers

    private func walkAndParse(folder: URL) async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        // Parallel parsing: collect paths first, then parse in task group
        var paths: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  isSupportedMediaFile(url) else { continue }
            paths.append(url)
        }

        let totalPaths = Double(max(paths.count, 1))
        var processed = 0

        await withTaskGroup(of: MediaItem?.self) { group in
            for path in paths {
                group.addTask { [metadataService] in
                    try? await metadataService.parse(url: path)
                }
                // Limit concurrency to avoid exhausting file descriptors
                if group.isEmpty == false && processed % 64 == 0 {
                    if let item = await group.next() ?? nil {
                        await MainActor.run {
                            if let item { self.state.upsert(item) }
                            processed += 1
                            self.state.scanProgress = Double(processed) / totalPaths
                        }
                    }
                }
            }
            for await item in group {
                await MainActor.run {
                    if let item { self.state.upsert(item) }
                    processed += 1
                    self.state.scanProgress = Double(processed) / totalPaths
                }
            }
        }
    }

    private func isSupportedMediaFile(_ url: URL) -> Bool {
        let audioExtensions: Set<String> = [
            "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "aiff",
            "aif", "alac", "wv", "m4b"
        ]
        let videoExtensions: Set<String> = ["mp4", "m4v", "mkv", "avi", "mov", "webm", "ts"]
        let ext = url.pathExtension.lowercased()
        return audioExtensions.contains(ext) || videoExtensions.contains(ext)
    }

    private func persistBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var dict = UserDefaults.standard.dictionary(forKey: persistenceKey) as? [String: Data] ?? [:]
        dict[url.path] = data
        UserDefaults.standard.set(dict, forKey: persistenceKey)
    }
}
