import Foundation
import AVFoundation
import CryptoKit

struct SubtitleCue: Hashable, Sendable {
    var startSeconds: Double
    var endSeconds: Double
    var text: String
}

struct SubtitleQuoteHit: Hashable, Sendable {
    var itemID: String
    var snippet: String
    var timestampSeconds: Double
}

enum SubtitleEngine {
    static func sidecarSRTURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("srt")
    }

    static func loadCues(for mediaURL: URL) -> [SubtitleCue] {
        let srtURL = sidecarSRTURL(for: mediaURL)
        return parseSRT(at: srtURL)
    }

    static func parseSRT(at url: URL) -> [SubtitleCue] {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parseSRT(content: content)
    }

    static func parseSRT(content: String) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard lines.count >= 3 else { continue }
            let timecodeLineIndex = lines[0].contains("-->") ? 0 : 1
            guard lines.indices.contains(timecodeLineIndex) else { continue }
            let timecodeLine = lines[timecodeLineIndex]

            guard let (start, end) = parseTimecode(line: timecodeLine), end >= start else {
                continue
            }

            let textStart = timecodeLineIndex + 1
            guard lines.indices.contains(textStart) else { continue }
            let text = lines[textStart...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: stripTags(from: text)))
        }

        return cues.sorted { $0.startSeconds < $1.startSeconds }
    }

    static func currentLine(at seconds: Double, cues: [SubtitleCue]) -> String? {
        guard !cues.isEmpty else { return nil }
        let current = max(0, seconds)
        if let cue = cues.first(where: { current >= $0.startSeconds && current < $0.endSeconds }) {
            return cue.text
        }
        return nil
    }

    static func searchQuotes(query: String, items: [MediaItem], limit: Int) -> [SubtitleQuoteHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var hits: [SubtitleQuoteHit] = []
        let maxHits = max(1, limit)

        for item in items where item.type_ == .video {
            let cues = loadCues(for: item.url)
            if cues.isEmpty { continue }

            for cue in cues {
                if cue.text.lowercased().contains(needle) {
                    hits.append(
                        SubtitleQuoteHit(
                            itemID: item.id,
                            snippet: cue.text,
                            timestampSeconds: cue.startSeconds
                        )
                    )
                    if hits.count >= maxHits {
                        return hits
                    }
                }
            }
        }

        return hits
    }

    static func searchQuotesInSingleVideo(query: String, mediaURL: URL, limit: Int) -> [SubtitleQuoteHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let cues = loadCues(for: mediaURL)
        guard !cues.isEmpty else { return [] }

        let maxHits = max(1, limit)
        var hits: [SubtitleQuoteHit] = []
        hits.reserveCapacity(min(cues.count, maxHits))

        let itemID = stableID(for: mediaURL)
        for cue in cues {
            if cue.text.lowercased().contains(needle) {
                hits.append(
                    SubtitleQuoteHit(
                        itemID: itemID,
                        snippet: cue.text,
                        timestampSeconds: cue.startSeconds
                    )
                )
                if hits.count >= maxHits {
                    break
                }
            }
        }

        return hits
    }

    private static func parseTimecode(line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseSingleTimecode(parts[0]),
              let end = parseSingleTimecode(parts[1]) else {
            return nil
        }
        return (start, end)
    }

    private static func parseSingleTimecode(_ raw: String) -> Double? {
        let tc = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = tc.split(separator: ":")
        guard parts.count == 3 else { return nil }

        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0

        let secParts = parts[2].split(separator: ".", maxSplits: 1).map(String.init)
        guard let seconds = Double(secParts[0]) else { return nil }
        let millis: Double
        if secParts.count > 1 {
            let fractional = String(secParts[1].prefix(3))
            millis = (Double(fractional) ?? 0) / 1000.0
        } else {
            millis = 0
        }

        return hours * 3600 + minutes * 60 + seconds + millis
    }

    private static func stripTags(from text: String) -> String {
        var out = ""
        var inAngle = false
        var inBrace = false
        for ch in text {
            switch ch {
            case "<": inAngle = true
            case ">": inAngle = false
            case "{": inBrace = true
            case "}": inBrace = false
            default:
                if !inAngle && !inBrace {
                    out.append(ch)
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableID(for mediaURL: URL) -> String {
        let path = mediaURL.standardizedFileURL.path
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
