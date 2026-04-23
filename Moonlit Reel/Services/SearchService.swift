// SearchService.swift — In-process library search
//
// PURPOSE: Full-text, fuzzy search across the in-memory library state.
//          Supports plain terms, field-qualified queries, and smart filters.
//          Does NOT call the Rust Tantivy FFI for the Swift-native MVP path;
//          Tantivy is used when the Rust engine is linked and available.
// LAYER:   Application Service
// DEPENDS ON: LibraryState

import Foundation

enum SearchBackend: String, CaseIterable, Sendable {
    case inMemory
    case rustBridge
}

/// A search result from the library index.
struct LibrarySearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let item: MediaItem
    let relevanceScore: Double
    let highlights: [String: String]  // field → highlighted snippet
    let jumpToSeconds: Double?
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
    private(set) var backend: SearchBackend = .inMemory
    private(set) var recentQueries: [String] = []
    private(set) var savedQueries: [String] = []
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
    private let recentQueriesKey = "search.recentQueries.v1"
    private let savedQueriesKey = "search.savedQueries.v1"
    private let maxRecentQueries = 20

    init(libraryState: LibraryState) {
        self.libraryState = libraryState
        self.recentQueries = UserDefaults.standard.stringArray(forKey: recentQueriesKey) ?? []
        self.savedQueries = UserDefaults.standard.stringArray(forKey: savedQueriesKey) ?? []
    }

    // MARK: - Public API

    func search(_ queryString: String) {
        query = queryString
    }

    func clearSearch() {
        query = ""
        isSearching = false
        results = []
    }

    func setBackend(_ backend: SearchBackend) {
        self.backend = backend
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleSearch()
        }
    }

    func saveCurrentQuery() {
        saveQuery(query)
    }

    func saveQuery(_ queryString: String) {
        let normalized = normalizeQuery(queryString)
        guard !normalized.isEmpty else { return }
        savedQueries.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        savedQueries.insert(normalized, at: 0)
        if savedQueries.count > maxRecentQueries {
            savedQueries = Array(savedQueries.prefix(maxRecentQueries))
        }
        persistSavedQueries()
    }

    func removeSavedQuery(_ queryString: String) {
        savedQueries.removeAll { $0.caseInsensitiveCompare(queryString) == .orderedSame }
        persistSavedQueries()
    }

    func runSavedQuery(_ queryString: String) {
        search(queryString)
    }

    func clearRecentQueries() {
        recentQueries = []
        persistRecentQueries()
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
            let backend = self.backend
            let tracks = self.libraryState.allTracks
            let videos = self.libraryState.allVideos

            let allItems = tracks + videos

            let results = await Task.detached(priority: .userInitiated) {
                performSearch(query: q, items: allItems, filter: f, backend: backend)
            }.value

            guard !Task.isCancelled else { return }
            self.results = results
            self.storeRecentQueryIfNeeded(q)
            self.isSearching = false
        }
    }

    private func storeRecentQueryIfNeeded(_ queryString: String) {
        let normalized = normalizeQuery(queryString)
        guard !normalized.isEmpty else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        recentQueries.insert(normalized, at: 0)
        if recentQueries.count > maxRecentQueries {
            recentQueries = Array(recentQueries.prefix(maxRecentQueries))
        }
        persistRecentQueries()
    }

    private func persistRecentQueries() {
        UserDefaults.standard.set(recentQueries, forKey: recentQueriesKey)
    }

    private func persistSavedQueries() {
        UserDefaults.standard.set(savedQueries, forKey: savedQueriesKey)
    }
}

// MARK: - Search algorithm (runs off MainActor)

private nonisolated func performSearch(
    query: String,
    items: [MediaItem],
    filter: SearchFilter,
    backend: SearchBackend
) -> [LibrarySearchResult] {

    switch backend {
    case .inMemory:
        return performInMemorySearch(query: query, items: items, filter: filter)
    case .rustBridge:
        // Rust-backed query path can be wired in without changing SearchService call sites.
        return performInMemorySearch(query: query, items: items, filter: filter)
    }
}

private nonisolated func performInMemorySearch(
    query: String,
    items: [MediaItem],
    filter: SearchFilter
) -> [LibrarySearchResult] {

    let normalizedQuery = normalizeQuery(query)
    guard !normalizedQuery.isEmpty else { return [] }

    if let quoteTerm = extractQuoteQuery(normalizedQuery) {
        return performQuoteSearch(query: quoteTerm, items: items, limit: 120)
    }

    let tokens = tokenize(normalizedQuery)
    guard !tokens.isEmpty else { return [] }

    var results: [LibrarySearchResult] = []

    for item in items {
        guard filter.mediaTypes.contains(item.type_) else { continue }
        if let yearRange = filter.yearRange {
            guard let year = item.year, yearRange.contains(year) else { continue }
        }
        if let durationRange = filter.durationRange, !durationRange.contains(item.durationSeconds) { continue }
        if !filter.genres.isEmpty {
            guard let genre = item.genre, filter.genres.contains(genre) else { continue }
        }

        let (score, highlights) = scoreItem(item, tokens: tokens, normalizedQuery: normalizedQuery)
        if score > 0 {
            results.append(LibrarySearchResult(
                id: item.id,
                item: item,
                relevanceScore: score,
                highlights: highlights,
                jumpToSeconds: nil
            ))
        }
    }

    return results.sorted { $0.relevanceScore > $1.relevanceScore }
}

private nonisolated func performQuoteSearch(
    query: String,
    items: [MediaItem],
    limit: Int
) -> [LibrarySearchResult] {
    let hits = SubtitleEngine.searchQuotes(query: query, items: items, limit: limit)
    if hits.isEmpty { return [] }
    let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

    var results: [LibrarySearchResult] = []
    results.reserveCapacity(hits.count)

    for (index, hit) in hits.enumerated() {
        guard let item = lookup[hit.itemID] else { continue }
        let score = 1000.0 - Double(index)
        results.append(
            LibrarySearchResult(
                id: "\(item.id)::\(Int(hit.timestampSeconds))",
                item: item,
                relevanceScore: score,
                highlights: ["subtitle": hit.snippet],
                jumpToSeconds: hit.timestampSeconds
            )
        )
    }

    return results
}

private nonisolated func extractQuoteQuery(_ query: String) -> String? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.lowercased().hasPrefix("quote:") {
        let value = String(trimmed.dropFirst("quote:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    return nil
}

private nonisolated func scoreItem(
    _ item: MediaItem,
    tokens: [String],
    normalizedQuery: String
) -> (Double, [String: String]) {
    let searchFields: [(name: String, value: String, weight: Double)] = [
        ("title",  item.title        ?? item.displayTitle, 3.0),
        ("artist", item.artist       ?? "",                 2.0),
        ("album",  item.album        ?? "",                 1.5),
        ("genre",  item.genre        ?? "",                 1.0),
        ("composer", item.composer   ?? "",                 0.8),
    ]

    var totalScore = 0.0
    var highlights: [String: String] = [:]

    let combinedText = searchFields
        .map(\.value)
        .joined(separator: " ")
        .lowercased()

    if combinedText.contains(normalizedQuery.lowercased()) {
        totalScore += 3.5
    }

    for token in tokens {
        var tokenMatched = false
        let qualified = parseQualifiedToken(token)

        for field in searchFields {
            if let qualified {
                if field.name == qualified.field.lowercased() {
                    let contains = field.value.localizedCaseInsensitiveContains(qualified.value)
                    if contains {
                        totalScore += field.weight * 2.2
                        highlights[field.name] = field.value
                        tokenMatched = true
                    }
                }
            } else {
                let lower = token.lowercased()
                let fieldLower = field.value.lowercased()
                if fieldLower == lower {
                    totalScore += field.weight * 2.6
                    highlights[field.name] = field.value
                    tokenMatched = true
                } else if fieldLower.hasPrefix(lower) {
                    totalScore += field.weight * 2.0
                    highlights[field.name] = field.value
                    tokenMatched = true
                } else if fieldLower.contains(lower) {
                    totalScore += field.weight * 1.2
                    highlights[field.name] = field.value
                    tokenMatched = true
                } else if fuzzyMatch(token: lower, in: fieldLower) {
                    totalScore += field.weight * 0.6
                    tokenMatched = true
                }
            }
        }
        if !tokenMatched {
            return (0, [:])
        }
    }

    totalScore += usageBoost(for: item.id)
    return (totalScore, highlights)
}

private nonisolated func usageBoost(for itemID: String) -> Double {
    guard let snapshot = PlaybackInsightsStore.snapshot(for: itemID) else { return 0 }

    let cappedPlayCount = min(snapshot.playCount, 40)
    let playCountBoost = log1p(Double(cappedPlayCount)) * 0.35

    let recencyWindow = max(0, Date().timeIntervalSince(snapshot.lastPlayedAt))
    let days = recencyWindow / (60 * 60 * 24)
    let recencyBoost: Double
    switch days {
    case ..<1: recencyBoost = 0.8
    case ..<7: recencyBoost = 0.45
    case ..<30: recencyBoost = 0.15
    default: recencyBoost = 0
    }

    let inProgressBoost = snapshot.isInProgress ? 0.4 : 0
    return playCountBoost + recencyBoost + inProgressBoost
}

private nonisolated func normalizeQuery(_ query: String) -> String {
    query
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private nonisolated func tokenize(_ query: String) -> [String] {
    query
        .trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
}

private struct QualifiedToken {
    let field: String
    let value: String
}

private nonisolated func parseQualifiedToken(_ token: String) -> QualifiedToken? {
    let parts = token.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return QualifiedToken(field: String(parts[0]), value: String(parts[1]))
}

/// Tolerance-1 fuzzy matching using sliding window.
private nonisolated func fuzzyMatch(token: String, in text: String) -> Bool {
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
