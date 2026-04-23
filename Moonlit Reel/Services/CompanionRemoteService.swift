import Foundation
import Network

@MainActor
@Observable
final class CompanionRemoteService {
    enum RemoteStatus: Equatable {
        case stopped
        case running(port: Int)
        case error(String)
    }

    private(set) var status: RemoteStatus = .stopped
    private(set) var isEnabled: Bool = false

    private let playerService: PlayerService
    private let libraryService: LibraryService

    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "moonlit.reel.remote.listener")
    private var defaultsObserver: NSObjectProtocol?

    private let enabledKey = "settings.httpRemoteEnabled"
    private let portKey = "settings.httpRemotePort"

    init(playerService: PlayerService, libraryService: LibraryService) {
        self.playerService = playerService
        self.libraryService = libraryService

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromSettings()
        }

        refreshFromSettings()
    }

    func refreshFromSettings() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: enabledKey)
        let rawPort = defaults.object(forKey: portKey) == nil ? 7177 : defaults.integer(forKey: portKey)
        applySettings(enabled: enabled, port: rawPort)
    }

    func applySettings(enabled: Bool, port: Int) {
        isEnabled = enabled

        if !enabled {
            stop()
            return
        }

        let boundedPort = max(1024, min(port, 65_535))
        if case .running(let runningPort) = status,
           runningPort == boundedPort,
           listener != nil {
            return
        }

        start(port: boundedPort)
    }

    private func start(port: Int) {
        stop()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            status = .error("Invalid port")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.status = .running(port: port)
                    case .failed(let error):
                        self.status = .error(error.localizedDescription)
                    case .cancelled:
                        self.status = .stopped
                    default:
                        break
                    }
                }
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        status = .stopped
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: listenerQueue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            guard let data,
                  let raw = String(data: data, encoding: .utf8),
                  let request = HTTPRequest.parse(raw: raw) else {
                Task { @MainActor in
                    self.send(connection: connection, status: 400, body: ["error": "Invalid request"])
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                let response = self.route(request)
                self.send(connection: connection, status: response.status, body: response.body)
            }
        }
    }

    private func route(_ request: HTTPRequest) -> (status: Int, body: [String: Any]) {
        switch (request.method.uppercased(), request.path) {
        case ("GET", "/status"):
            return (200, statusPayload())

        case ("GET", "/queue"):
            return (200, queuePayload())

        case ("POST", "/playpause"):
            playerService.togglePlayPause()
            return (200, statusPayload())

        case ("POST", "/next"):
            playerService.playNext()
            return (200, statusPayload())

        case ("POST", "/previous"):
            playerService.playPrevious()
            return (200, statusPayload())

        case ("POST", "/seek"):
            guard let secondsText = request.queryItems["seconds"],
                  let seconds = Double(secondsText) else {
                return (400, ["error": "Missing or invalid seconds"])
            }
            playerService.seek(to: seconds)
            return (200, statusPayload())

        case ("POST", "/volume"):
            guard let valueText = request.queryItems["value"],
                  let value = Double(valueText) else {
                return (400, ["error": "Missing or invalid value"])
            }
            playerService.setVolume(Float(value))
            return (200, statusPayload())

        case ("POST", "/queue/clear"):
            playerService.state.replaceQueue([])
            return (200, statusPayload())

        case ("POST", "/queue/play"):
            guard let id = request.queryItems["id"] else {
                return (400, ["error": "Missing id"])
            }
            let allItems = libraryService.state.allTracks + libraryService.state.allVideos
            guard let item = allItems.first(where: { $0.id == id }) else {
                return (404, ["error": "Item not found"])
            }
            playerService.play(item)
            return (200, statusPayload())

        default:
            return (404, ["error": "Not found"])
        }
    }

    private func statusPayload() -> [String: Any] {
        [
            "isPlaying": playerService.state.isPlaying,
            "status": statusString(playerService.state.status),
            "title": playerService.state.currentItem?.displayTitle ?? "",
            "artist": playerService.state.currentItem?.displayArtist ?? "",
            "position": playerService.state.positionSeconds,
            "duration": playerService.state.currentDuration,
            "queueCount": playerService.state.queue.count,
            "queueIndex": playerService.state.queueIndex
        ]
    }

    private func queuePayload() -> [String: Any] {
        let items: [[String: Any]] = playerService.state.queue.map { item in
            [
                "id": item.id,
                "title": item.displayTitle,
                "artist": item.displayArtist,
                "duration": item.durationSeconds
            ]
        }
        return [
            "currentIndex": playerService.state.queueIndex,
            "items": items
        ]
    }

    private func send(connection: NWConnection, status: Int, body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data("{}".utf8)
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(json)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Error"
        }
    }

    private func statusString(_ status: PlaybackStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .loading: return "loading"
        case .playing: return "playing"
        case .paused: return "paused"
        case .ended: return "ended"
        case .error(let message): return "error: \(message)"
        }
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var queryItems: [String: String]

    static func parse(raw: String) -> HTTPRequest? {
        guard let requestLine = raw.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let pathWithQuery = String(parts[1])

        let components = URLComponents(string: "http://localhost\(pathWithQuery)")
        let path = components?.path ?? "/"
        var queryItems: [String: String] = [:]
        components?.queryItems?.forEach { item in
            queryItems[item.name] = item.value ?? ""
        }

        return HTTPRequest(method: method, path: path, queryItems: queryItems)
    }
}
