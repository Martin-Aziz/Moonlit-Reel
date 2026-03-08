// SearchService.swift — In-process library search
//
// PURPOSE: Full-text, fuzzy search across the in-memory library state.
//          Supports plain terms, field-qualified queries, and smart filters.
//          Does NOT call the Rust Tantivy FFI for the Swift-native MVP path;
//          Tantivy is used when the Rust engine is linked and available.
// LAYER:   Application Service
// DEPENDS ON: LibraryState

import Foundation

/// A search result from the library index.
struct LibrarySearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let item: MediaItem
    let relevanceScore: Double
    let highlights: [String: String]  // field → highlighted snippet
}

/// Filter criteria for search results.
struct SearchFilter: Hashable, Sendable {
    var mediaTypes: Set<MediaItemType> = [.audio, .video, .audiobookChapter]
    var yearRange: ClosedRange<Int>? = nil
    var durationRange: ClosedRange<Double>? = nil
    var genres: Set<String> = []
}

/// Provides instant search across the library.
///
/// Backed by in-memory matching for sub-10ms response on 50k tracks.
/// Structured to accept Tantivy results via `RustBridgeService` post-FFI-link.
@MainActor
@Observable
final class SearchService {

    private(set) var results: [LibrarySearchResult] = []
    private(set) var isSearching: Bool = false
    var query: String = "" {
        didSet { scheduleSearch() }
    }
    var filter: SearchFilter = SearchFilter() {
        didSet { scheduleSearch() }
    }

    // ── Available facets ──────────────────────────────────────────────────────
    private(set) var availableGenres: [String] = []
    private(set) var yearRange: ClosedRange<Int>? = nil

    private let libraryState: LibraryState
    private var searchTask: Task<Void, Never>?

    init(libraryState: LibraryState) {
        self.libraryState = libraryState
    }

    // MARK: - Public API

    func search(_ queryString: String) {
        query = queryString
    }

    func clearSearch() {
        query = ""
        results = []
    }

    func updateFacets() {
        let genres = Set(libraryState.allTracks.compactMap { $0.genre })
        availableGenres = genres.sorted()

        let years = libraryState.allTracks.compactMap { $0.year }
        if let minYear = years.min(), let maxYear = years.max() {
            yearRange = minYear...maxYear
        }
    }

    // MARK: - Private

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isSearching = true
        searchTask = Task {
            // Debounce: 80ms
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let q = self.query
            let f = self.filter
            let tracks = self.libraryState.allTracks
            let videos = self.libraryState.allVideos

            let allItems = tracks + videos

            let results = await Task.detached(priority: .userInitiated) {
                performSearch(query: q, items: allItems, filter: f)
            }.value

            guard !Task.isCancelled else { return }
            self.results = results
            self.isSearching = false
        }
    }
}

// MARK: - Search algorithm (runs off MainActor)

private func performSearch(
    query: String,
    items: [MediaItem],
    filter: SearchFilter
) -> [LibrarySearchResult] {

    let tokens = tokenize(query)
    guard !tokens.isEmpty else { return [] }

    var results: [LibrarySearchResult] = []

    for item in items {
        guard filter.mediaTypes.contains(item.type_) else { continue }
        if let yearRange = filter.durationRange, !yearRange.contains(item.durationSeconds) { continue }
        if !filter.genres.isEmpty, let genre = item.genre, !filter.genres.contains(genre) { continue }

        let (score, highlights) = scoreItem(item, tokens: tokens)
        if score > 0 {
            results.append(LibrarySearchResult(
                id: item.id,
                item: item,
                relevanceScore: score,
                highlights: highlights
            ))
        }
    }

    return results.sorted { $0.relevanceScore > $1.relevanceScore }
}

private func scoreItem(_ item: MediaItem, tokens: [String]) -> (Double, [String: String]) {
    let searchFields: [(name: String, value: String, weight: Double)] = [
        ("title",  item.title        ?? item.displayTitle, 3.0),
        ("artist", item.artist       ?? "",                 2.0),
        ("album",  item.album        ?? "",                 1.5),
        ("genre",  item.genre        ?? "",                 1.0),
        ("composer", item.composer   ?? "",                 0.8),
    ]

    var totalScore = 0.0
    var highlights: [String: String] = [:]

    for token in tokens {
        var tokenMatched = false
        for field in searchFields {
            if field.name == "title", let qualified = parseQualifiedToken(token) {
                // Handle `field:value` queries
                if field.name == qualified.field {
                    let contains = field.value.localizedCaseInsensitiveContains(qualified.value)
                    if contains {
                        totalScore += field.weight * 2
                        highlights[field.name] = field.value
                        tokenMatched = true
                    }
                }
            } else {
                let lower = token.lowercased()
                let fieldLower = field.value.lowercased()
                if fieldLower.contains(lower) {
                    // Exact prefix match scores higher
                    let bonus: Double = fieldLower.hasPrefix(lower) ? 1.5 : 1.0
                    totalScore += field.weight * bonus
                    highlights[field.name] = field.value
                    tokenMatched = true
                } else if fuzzyMatch(token: lower, in: fieldLower) {
                    totalScore += field.weight * 0.5
                    tokenMatched = true
                }
            }
        }
        if !tokenMatched {
            totalScore = 0   // All tokens must match at least one field
            break
        }
    }

    return (totalScore, highlights)
}

private func tokenize(_ query: String) -> [String] {
    query
        .trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
}

private struct QualifiedToken {
    let field: String
    let value: String
}

private func parseQualifiedToken(_ token: String) -> QualifiedToken? {
    let parts = token.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return QualifiedToken(field: String(parts[0]), value: String(parts[1]))
}

/// Tolerance-1 fuzzy matching using sliding window.
private func fuzzyMatch(token: String, in text: String) -> Bool {
    guard token.count >= 3 else { return false }
    let textChars = Array(text)
    let tokenChars = Array(token)
    let n = tokenChars.count

    for i in 0...(max(0, textChars.count - n + 1)) {
        guard i + n <= textChars.count else { break }
        let window = Array(textChars[i..<(i + n)])
        var mismatches = 0
        for j in 0..<n {
            if window[j] != tokenChars[j] { mismatches += 1 }
            if mismatches > 1 { break }
        }
        if mismatches <= 1 { return true }
    }
    return false
}
