import Foundation

struct ListeningSnapshot: Codable, Hashable, Sendable {
    var itemID: String
    var lastPlayedAt: Date
    var lastPositionSeconds: Double
    var durationSeconds: Double
    var playCount: Int

    var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return (lastPositionSeconds / durationSeconds).clamped(0, 1)
    }

    var isInProgress: Bool {
        let p = progressFraction
        return p > 0.02 && p < 0.98
    }
}

struct AdaptiveEqProfile: Codable, Hashable, Sendable {
    var gainsDB: [Float]
    var updatedAt: Date
}

enum PlaybackInsightsStore {
    private static let listeningHistoryKey = "insights.listeningHistory.v1"
    private static let adaptiveEqKey = "insights.adaptiveEqProfiles.v1"
    private static let maxHistoryEntries = 1000

    static func recordPlayStart(itemID: String, durationSeconds: Double) {
        guard !itemID.isEmpty else { return }
        var history = loadHistoryMap()
        var snapshot = history[itemID] ?? ListeningSnapshot(
            itemID: itemID,
            lastPlayedAt: Date(),
            lastPositionSeconds: 0,
            durationSeconds: max(0, durationSeconds),
            playCount: 0
        )
        snapshot.lastPlayedAt = Date()
        snapshot.playCount += 1
        if durationSeconds > 0 {
            snapshot.durationSeconds = durationSeconds
        }
        history[itemID] = snapshot
        saveHistoryMap(trim(history: history))
    }

    static func recordProgress(itemID: String, positionSeconds: Double, durationSeconds: Double) {
        guard !itemID.isEmpty else { return }
        var history = loadHistoryMap()
        var snapshot = history[itemID] ?? ListeningSnapshot(
            itemID: itemID,
            lastPlayedAt: Date(),
            lastPositionSeconds: 0,
            durationSeconds: max(0, durationSeconds),
            playCount: 1
        )
        snapshot.lastPlayedAt = Date()
        if durationSeconds > 0 {
            snapshot.durationSeconds = durationSeconds
        }
        snapshot.lastPositionSeconds = positionSeconds.clamped(0, max(snapshot.durationSeconds, positionSeconds))
        history[itemID] = snapshot
        saveHistoryMap(trim(history: history))
    }

    static func continueItemIDs(limit: Int = 8) -> [String] {
        let snapshots = loadHistoryMap().values
        return snapshots
            .sorted(by: compareSnapshots)
            .prefix(max(0, limit))
            .map(\.itemID)
    }

    static func sessionSeedItemIDs(limit: Int = 32) -> [String] {
        let snapshots = loadHistoryMap().values
        return snapshots
            .sorted(by: compareSnapshots)
            .prefix(max(0, limit))
            .map(\.itemID)
    }

    static func snapshot(for itemID: String) -> ListeningSnapshot? {
        loadHistoryMap()[itemID]
    }

    static func adaptiveEqProfile(for contextKey: String) -> AdaptiveEqProfile? {
        loadEqMap()[contextKey]
    }

    static func saveAdaptiveEqProfile(_ profile: AdaptiveEqProfile, contextKey: String) {
        guard !contextKey.isEmpty else { return }
        var map = loadEqMap()
        map[contextKey] = profile
        saveEqMap(map)
    }

    private static func compareSnapshots(_ lhs: ListeningSnapshot, _ rhs: ListeningSnapshot) -> Bool {
        if lhs.isInProgress != rhs.isInProgress {
            return lhs.isInProgress && !rhs.isInProgress
        }
        if lhs.lastPlayedAt != rhs.lastPlayedAt {
            return lhs.lastPlayedAt > rhs.lastPlayedAt
        }
        return lhs.playCount > rhs.playCount
    }

    private static func trim(history: [String: ListeningSnapshot]) -> [String: ListeningSnapshot] {
        guard history.count > maxHistoryEntries else { return history }
        let keepIDs = history
            .values
            .sorted(by: compareSnapshots)
            .prefix(maxHistoryEntries)
            .map(\.itemID)
        let keepSet = Set(keepIDs)
        return history.filter { keepSet.contains($0.key) }
    }

    private static func loadHistoryMap() -> [String: ListeningSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: listeningHistoryKey),
              let decoded = try? JSONDecoder().decode([String: ListeningSnapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveHistoryMap(_ map: [String: ListeningSnapshot]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: listeningHistoryKey)
    }

    private static func loadEqMap() -> [String: AdaptiveEqProfile] {
        guard let data = UserDefaults.standard.data(forKey: adaptiveEqKey),
              let decoded = try? JSONDecoder().decode([String: AdaptiveEqProfile].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveEqMap(_ map: [String: AdaptiveEqProfile]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: adaptiveEqKey)
    }
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
