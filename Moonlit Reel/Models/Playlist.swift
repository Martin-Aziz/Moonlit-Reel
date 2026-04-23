// Playlist.swift — Smart + static playlist domain models
//
// PURPOSE: Defines static (user-curated) and smart (rule-based) playlists.
// LAYER:   Domain Model

import Foundation
import SwiftUI

// MARK: - Static Playlist

/// A user-curated ordered list of media items.
struct Playlist: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var trackIDs: [String]   /// Ordered list of `MediaItem.id`
    var createdAt: Date
    var updatedAt: Date

    init(name: String) {
        self.id        = UUID()
        self.name      = name
        self.trackIDs  = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var trackCount: Int { trackIDs.count }

    mutating func append(_ itemID: String) {
        guard !trackIDs.contains(itemID) else { return }
        trackIDs.append(itemID)
        updatedAt = Date()
    }

    mutating func remove(id itemID: String) {
        trackIDs.removeAll { $0 == itemID }
        updatedAt = Date()
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        trackIDs.move(fromOffsets: source, toOffset: destination)
        updatedAt = Date()
    }
}

// MARK: - Smart Playlist

/// A rule used in a `SmartPlaylist` filter.
struct SmartRule: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var field: SmartRuleField
    var op: SmartRuleOperator
    var value: SmartRuleValue

    init(field: SmartRuleField, op: SmartRuleOperator, value: SmartRuleValue) {
        self.id    = UUID()
        self.field = field
        self.op    = op
        self.value = value
    }
}

enum SmartRuleField: String, Codable, CaseIterable, Identifiable {
    case title, artist, album, genre, year
    case trackNumber, discNumber, bpm
    case durationSeconds, fileSizeBytes
    case playCount, skipCount, rating
    case dateAdded, lastPlayed

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum SmartRuleOperator: String, Codable, CaseIterable, Identifiable {
    case contains, notContains
    case equals, notEquals
    case startsWith, endsWith
    case greaterThan, lessThan, greaterOrEqual, lessOrEqual
    case inLast    // date fields: "in the last N days"

    var id: String { rawValue }
}

/// Boxed value for a smart rule (union of string, int, double, date).
enum SmartRuleValue: Hashable, Codable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
}

/// Logical combination for multiple rules.
enum SmartRuleConjunction: String, Codable, CaseIterable {
    case all  = "All (AND)"
    case any  = "Any (OR)"
}

/// A dynamically evaluated playlist driven by a set of rules.
struct SmartPlaylist: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var rules: [SmartRule]
    var conjunction: SmartRuleConjunction
    var limitCount: Int?            // nil = no limit
    var sortField: SmartRuleField?
    var sortAscending: Bool

    init(name: String) {
        self.id            = UUID()
        self.name          = name
        self.rules         = []
        self.conjunction   = .all
        self.limitCount    = nil
        self.sortField     = nil
        self.sortAscending = true
    }

    /// Evaluate the rules against a single `MediaItem`.
    ///
    /// Returns `true` if the item matches according to the conjunction.
    func matches(_ item: MediaItem) -> Bool {
        guard !rules.isEmpty else { return true }
        let results = rules.map { evaluate($0, item: item) }
        return conjunction == .all
            ? results.allSatisfy { $0 }
            : results.contains { $0 }
    }

    private func evaluate(_ rule: SmartRule, item: MediaItem) -> Bool {
        switch rule.field {
        case .title:
            return matchString(rule, value: item.title ?? "")
        case .artist:
            return matchString(rule, value: item.artist ?? "")
        case .album:
            return matchString(rule, value: item.album ?? "")
        case .genre:
            return matchString(rule, value: item.genre ?? "")
        case .year:
            return matchInt(rule, value: item.year ?? 0)
        case .bpm:
            return matchInt(rule, value: item.bpm ?? 0)
        case .durationSeconds:
            return matchDouble(rule, value: item.durationSeconds)
        case .trackNumber:
            return matchInt(rule, value: item.trackNumber ?? 0)
        case .discNumber:
            return matchInt(rule, value: item.discNumber ?? 0)
        case .fileSizeBytes:
            return matchInt(rule, value: item.fileSizeBytes)
        default:
            return true  // Unimplemented fields default to match
        }
    }

    private func matchString(_ rule: SmartRule, value: String) -> Bool {
        guard case .text(let target) = rule.value else { return false }
        switch rule.op {
        case .contains:    return value.localizedCaseInsensitiveContains(target)
        case .notContains: return !value.localizedCaseInsensitiveContains(target)
        case .equals:      return value.caseInsensitiveCompare(target) == .orderedSame
        case .notEquals:   return value.caseInsensitiveCompare(target) != .orderedSame
        case .startsWith:  return value.lowercased().hasPrefix(target.lowercased())
        case .endsWith:    return value.lowercased().hasSuffix(target.lowercased())
        default:           return false
        }
    }

    private func matchInt(_ rule: SmartRule, value: Int) -> Bool {
        guard case .integer(let target) = rule.value else { return false }
        switch rule.op {
        case .equals:         return value == target
        case .notEquals:      return value != target
        case .greaterThan:    return value >  target
        case .lessThan:       return value <  target
        case .greaterOrEqual: return value >= target
        case .lessOrEqual:    return value <= target
        default:              return false
        }
    }

    private func matchDouble(_ rule: SmartRule, value: Double) -> Bool {
        let target: Double
        switch rule.value {
        case .decimal(let d): target = d
        case .integer(let i): target = Double(i)
        default: return false
        }
        switch rule.op {
        case .greaterThan:    return value >  target
        case .lessThan:       return value <  target
        case .greaterOrEqual: return value >= target
        case .lessOrEqual:    return value <= target
        default:              return false
        }
    }
}
