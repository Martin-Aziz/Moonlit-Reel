// AppEnvironment.swift — Dependency injection via @Environment
//
// PURPOSE: Typed @Environment keys for all app-level services.
//          Services are created once in Moonlit_ReelApp.init() and injected
//          into the SwiftUI environment hierarchy.
// LAYER:   Presentation / DI

import SwiftUI

// MARK: - Environment Keys

struct PlayerServiceKey: EnvironmentKey {
    static let defaultValue = PlayerService()
}

struct LibraryServiceKey: EnvironmentKey {
    static let defaultValue: LibraryService = {
        LibraryService()
    }()
}

struct AudiobookServiceKey: EnvironmentKey {
    static let defaultValue: AudiobookService = {
        let ps = PlayerService()
        let ls = LibraryService()
        return AudiobookService(playerService: ps, libraryState: ls.state)
    }()
}

struct SearchServiceKey: EnvironmentKey {
    static let defaultValue: SearchService = {
        SearchService(libraryState: LibraryServiceKey.defaultValue.state)
    }()
}

struct MetadataServiceKey: EnvironmentKey {
    static let defaultValue = MetadataService()
}

struct ThemeServiceKey: EnvironmentKey {
    static let defaultValue = ThemeService()
}

// MARK: - EnvironmentValues Extensions

extension EnvironmentValues {
    var playerService: PlayerService {
        get { self[PlayerServiceKey.self] }
        set { self[PlayerServiceKey.self] = newValue }
    }

    var libraryService: LibraryService {
        get { self[LibraryServiceKey.self] }
        set { self[LibraryServiceKey.self] = newValue }
    }

    var audiobookService: AudiobookService {
        get { self[AudiobookServiceKey.self] }
        set { self[AudiobookServiceKey.self] = newValue }
    }

    var searchService: SearchService {
        get { self[SearchServiceKey.self] }
        set { self[SearchServiceKey.self] = newValue }
    }

    var metadataService: MetadataService {
        get { self[MetadataServiceKey.self] }
        set { self[MetadataServiceKey.self] = newValue }
    }

    var themeService: ThemeService {
        get { self[ThemeServiceKey.self] }
        set { self[ThemeServiceKey.self] = newValue }
    }
}
