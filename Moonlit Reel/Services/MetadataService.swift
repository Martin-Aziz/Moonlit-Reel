// MetadataService.swift — AVFoundation-based metadata parsing
//
// PURPOSE: Extracts tags, duration, artwork and technical properties from media files.
//          Uses AVFoundation as primary parser; falls back gracefully on failure.
// LAYER:   Infrastructure Service
// PERFORMANCE: Called from background tasks; must not touch MainActor state.

import Foundation
import AVFoundation

/// Stateless metadata parser. Thread-safe; can be shared across tasks.
final class MetadataService: Sendable {

    nonisolated init() {}

    /// Parse a media file URL and return a `MediaItem`.
    ///
    /// - Parameter url: Local file URL of a media file.
    /// - Returns: A populated `MediaItem`, never nil (uses filename fallback).
    /// - Throws: When the file cannot be opened or is unsupported.
    func parse(url: URL) async throws -> MediaItem {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        async let durationTask     = asset.load(.duration)
        async let tracksTask       = asset.loadTracks(withMediaType: .audio)
        async let metadataTask     = asset.load(.commonMetadata)
        async let formatsTask      = asset.load(.availableMetadataFormats)

        let duration   = try await durationTask
        let audioTracks = try await tracksTask
        let common     = try await metadataTask
        let formats    = try await formatsTask

        // Collect all metadata items across all formats
        var allMetaItems: [AVMetadataItem] = common
        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            allMetaItems.append(contentsOf: items)
        }

        let meta = MetadataExtractor(items: allMetaItems)

        // Technical properties from the audio track
        let audioTrack = audioTracks.first
        let sampleRate: Int? = await {
            guard let track = audioTrack,
                  let desc = try? await track.load(.formatDescriptions).first else { return nil }
            return Int(CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee.mSampleRate ?? 0)
        }()

        let bitRate: Int? = await {
            guard let track = audioTrack,
                  let bps = try? await track.load(.estimatedDataRate) else { return nil }
            return Int(bps)
        }()

        let channelCount: Int? = await {
            guard let track = audioTrack,
                  let desc = try? await track.load(.formatDescriptions).first else { return nil }
            return Int(CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee.mChannelsPerFrame ?? 0)
        }()

        // Artwork loaded on-demand via artwork(for:); skip here to avoid unused-var warning.
        let fsAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fsAttrs?[.size] as? Int) ?? 0
        let mtime = (fsAttrs?[.modificationDate] as? Date) ?? Date.distantPast

        let mediaType = classify(url: url)
        let id = stableID(for: url)

        return MediaItem(
            id: id,
            url: url,
            type_: mediaType,
            title: meta.string(.commonIdentifierTitle),
            artist: meta.string(.commonIdentifierArtist) ?? meta.string(.iTunes(.artist)),
            albumArtist: meta.string(.iTunes(.albumArtist)),
            album: meta.string(.commonIdentifierAlbumName),
            genre: meta.string(.commonIdentifierType) ?? meta.string(.iTunes(.genre)),
            year: meta.year(),
            trackNumber: meta.int(.iTunes(.trackNumber)),
            discNumber: meta.int(.iTunes(.discNumber)),
            composer: meta.string(.iTunes(.composer)),
            comment: meta.string(.commonIdentifierDescription),
            bpm: meta.int(.iTunes(.beatsPerMinute)),
            durationSeconds: max(0, CMTimeGetSeconds(duration)),
            sampleRate: sampleRate,
            bitRate: bitRate,
            channelCount: channelCount,
            codec: nil,
            fileSizeBytes: fileSize,
            modifiedAt: mtime,
            replayGainTrackDB: nil,
            replayGainAlbumDB: nil
        )
    }

    // MARK: - Artwork

    /// Returns artwork data (JPEG/PNG) from the asset metadata.
    func artwork(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        return await extractArtwork(from: asset, items: items)
    }

    // MARK: - Private

    private func extractArtwork(from asset: AVURLAsset, items: [AVMetadataItem]) async -> Data? {
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) {
                return data
            }
        }
        return nil
    }

    private func classify(url: URL) -> MediaItemType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m4b":
            return .audiobookChapter
        case "mp4", "m4v", "mkv", "avi", "mov", "webm", "ts":
            return .video
        default:
            return .audio
        }
    }

    private func stableID(for url: URL) -> String {
        // Mirror Rust BLAKE3 hashing: use path string → SHA256 (Swift doesn't have BLAKE3 natively)
        // For Swift-native scanning, SHA256 of the canonical path provides a stable ID.
        let path = url.standardizedFileURL.path
        return path.data(using: .utf8).map { sha256Hex($0) } ?? UUID().uuidString
    }
}

// MARK: - Metadata extraction helpers

private struct MetadataExtractor {
    let items: [AVMetadataItem]

    func string(_ key: AVMetadataIdentifier) -> String? {
        value(for: key) as? String
    }

    func string(_ key: AVMetadataKey, space: AVMetadataKeySpace = .common) -> String? {
        items.first { $0.key as? String == key.rawValue }
            .flatMap { ($0 as AnyObject).value(forKeyPath: "stringValue") as? String }
    }

    func int(_ key: AVMetadataIdentifier) -> Int? {
        if let n = value(for: key) as? NSNumber { return n.intValue }
        if let s = value(for: key) as? String, let n = Int(s.split(separator: "/").first ?? "") { return n }
        return nil
    }

    func year() -> Int? {
        // Try multiple year sources
        if let s = string(.commonIdentifierCreationDate) ?? string(.iTunes(.releaseDate)) {
            return Int(s.prefix(4))
        }
        return nil
    }

    private func value(for identifier: AVMetadataIdentifier) -> (NSCopying & NSObjectProtocol)? {
        guard let item = items.first(where: { $0.identifier == identifier }) else { return nil }
        return (item as AnyObject).value(forKeyPath: "value") as? (NSCopying & NSObjectProtocol)
    }
}

private extension AVMetadataIdentifier {
    // Shorthand for iTunes-namespace identifiers
    static func iTunes(_ key: AVMetadataKey) -> AVMetadataIdentifier {
        AVMetadataItem.identifier(forKey: key, keySpace: .iTunes) ??
            AVMetadataIdentifier("itsk/\(key.rawValue)")
    }
}

private extension AVMetadataKey {
    static let albumArtist     = AVMetadataKey(rawValue: "TPE2")
    static let artist          = AVMetadataKey(rawValue: "©ART")
    static let album           = AVMetadataKey(rawValue: "©alb")
    static let genre           = AVMetadataKey(rawValue: "©gen")
    static let composer        = AVMetadataKey(rawValue: "©wrt")
    static let trackNumber     = AVMetadataKey(rawValue: "trkn")
    static let discNumber      = AVMetadataKey(rawValue: "disk")
    static let beatsPerMinute  = AVMetadataKey(rawValue: "tmpo")
    static let releaseDate     = AVMetadataKey(rawValue: "©day")
}

// MARK: - SHA256 hex helper (for stable track IDs from Swift-side scanning)

import CryptoKit

private func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}
