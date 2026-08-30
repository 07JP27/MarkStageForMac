import Foundation
import Network

final class PresentationServer: @unchecked Sendable {
    private let session: PresentationSession
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private let queue = DispatchQueue(label: "dev.jp27.MarkdStage.presentation-server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var observerID: UUID?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var eventConnections: [ObjectIdentifier: NWConnection] = [:]
    private var currentPort: UInt16?
    private var presenterRunning = false
    private let webRoot: URL

    init(session: PresentationSession, webRoot: URL? = nil) throws {
        self.session = session
        if let webRoot {
            self.webRoot = PathSecurity.canonicalURL(webRoot)
        } else {
            let bundle = Bundle(for: PresentationServer.self)
            guard let bundledRoot = bundle.url(forResource: "Web", withExtension: nil) else {
                throw DeckLoadError(message: "Presentation renderer assets are missing.")
            }
            self.webRoot = PathSecurity.canonicalURL(bundledRoot)
        }
        guard FileManager.default.fileExists(
            atPath: self.webRoot.appendingPathComponent("index.html").path
        ) else {
            throw DeckLoadError(message: "Presentation renderer assets are missing.")
        }
    }

    var baseURL: URL? {
        stateLock.withLock {
            guard let currentPort else { return nil }
            return URL(string: "http://127.0.0.1:\(currentPort)/\(token)/")
        }
    }

    func start() throws {
        if stateLock.withLock({ currentPort != nil }) {
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let startState = ListenerStartState()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else {
                    startState.finish(.failure(DeckLoadError(message: "Presentation server did not expose a port.")))
                    return
                }
                startState.finish(.success(port))
            case let .failed(error):
                startState.finish(.failure(error))
            case .cancelled:
                startState.finish(.failure(DeckLoadError(message: "Presentation server stopped during startup.")))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)

        guard startState.semaphore.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            self.listener = nil
            throw DeckLoadError(message: "Presentation server timed out during startup.")
        }

        switch startState.result {
        case let .success(port):
            stateLock.withLock {
                currentPort = port
            }
            observerID = session.addObserver { [weak self] snapshot in
                self?.broadcast(version: snapshot.version)
            }
        case let .failure(error):
            listener.cancel()
            self.listener = nil
            throw DeckLoadError(message: "Presentation server could not start: \(error.localizedDescription)")
        case .none:
            listener.cancel()
            self.listener = nil
            throw DeckLoadError(message: "Presentation server returned no startup result.")
        }
    }

    func stop() {
        if let observerID {
            session.removeObserver(observerID)
            self.observerID = nil
        }
        listener?.cancel()
        listener = nil
        queue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            eventConnections.removeAll()
        }
        stateLock.withLock {
            currentPort = nil
        }
    }

    func setPresenterRunning(_ running: Bool) {
        stateLock.withLock {
            presenterRunning = running
        }
        broadcast(version: session.currentSnapshot().version)
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .cancelled, .failed:
                guard let self, let connection else { return }
                self.queue.async {
                    let id = ObjectIdentifier(connection)
                    self.connections.removeValue(forKey: id)
                    self.eventConnections.removeValue(forKey: id)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }
            if buffer.count > 128 * 1024 {
                self.send(.text("Request too large.", status: 413), on: connection)
                return
            }
            if let request = HTTPRequest.parse(buffer) {
                self.route(request, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        guard let port = stateLock.withLock({ currentPort }) else {
            send(.text("Server unavailable.", status: 503), on: connection)
            return
        }
        let expectedHost = "127.0.0.1:\(port)"
        guard request.headers["host"] == expectedHost else {
            send(.text("Forbidden.", status: 403), on: connection)
            return
        }
        if request.method == "POST",
           let origin = request.headers["origin"],
           origin != "http://\(expectedHost)" {
            send(.text("Forbidden.", status: 403), on: connection)
            return
        }

        guard let components = URLComponents(string: "http://\(expectedHost)\(request.target)"),
              components.path.hasPrefix("/\(token)") else {
            send(.text("Not found.", status: 404), on: connection)
            return
        }
        var routePath = String(components.path.dropFirst(token.count + 1))
        if routePath.isEmpty { routePath = "/" }

        switch (request.method, routePath) {
        case ("GET", "/"), ("GET", "/index.html"):
            sendFile(webRoot.appendingPathComponent("index.html"), on: connection)
        case ("GET", let path) where path.hasPrefix("/renderer/"):
            sendStatic(
                root: webRoot.appendingPathComponent("renderer", isDirectory: true),
                relativePath: String(path.dropFirst("/renderer/".count)),
                on: connection
            )
        case ("GET", let path) where path.hasPrefix("/vendor/"):
            sendStatic(
                root: webRoot.appendingPathComponent("vendor", isDirectory: true),
                relativePath: String(path.dropFirst("/vendor/".count)),
                on: connection
            )
        case ("GET", "/state"):
            sendState(offset: components.queryItem(named: "offset").flatMap(Int.init) ?? 0, on: connection)
        case ("GET", "/deck"):
            sendDeck(on: connection)
        case ("POST", "/navigate"):
            navigate(request, on: connection)
        case ("GET", "/events"):
            openEventStream(connection)
        case ("GET", let path) where path.hasPrefix("/assets/"):
            sendDeckAsset(String(path.dropFirst("/assets/".count)), on: connection)
        case ("GET", let path) where path.hasPrefix("/theme-assets/"):
            sendThemeAsset(String(path.dropFirst("/theme-assets/".count)), on: connection)
        case ("GET", "/export-data"):
            sendExportData(on: connection)
        case ("POST", "/export-status"):
            send(.json(["ok": true]), on: connection)
        default:
            send(.text("Not found.", status: 404), on: connection)
        }
    }

    private func sendState(offset: Int, on connection: NWConnection) {
        let snapshot = session.currentSnapshot()
        let safeOffset = min(max(offset, -1), 1)
        let target = snapshot.total == 0
            ? 0
            : min(max(snapshot.index + safeOffset, 0), snapshot.total - 1)
        let markdown = snapshot.total == 0 ? "" : snapshot.slides[target]
        let customThemeMeta = snapshot.theme.metadataJSON.isEmpty
            ? NSNull()
            : (try? JSONSerialization.jsonObject(
                with: Data(snapshot.theme.metadataJSON.utf8)
            )) ?? NSNull()
        let isPresenterRunning = stateLock.withLock { presenterRunning }
        send(.json([
            "version": snapshot.version,
            "deckVersion": snapshot.deckVersion,
            "markdown": markdown,
            "index": target,
            "total": snapshot.total,
            "theme": snapshot.theme.name,
            "themeLocked": false,
            "customThemeCss": snapshot.theme.css,
            "customThemeMeta": customThemeMeta,
            "mode": "deck",
            "sourceBacked": snapshot.sourceURL != nil,
            "sourceMode": "live",
            "sourceWatchStatus": snapshot.sourceURL == nil ? "inactive" : "watching",
            "sourceWatchError": "",
            "presenterRunning": isPresenterRunning,
            "architectureEdit": false,
            "architectureDetailedEdit": false
        ]), on: connection)
    }

    private func sendDeck(on connection: NWConnection) {
        let snapshot = session.currentSnapshot()
        send(.json([
            "deckVersion": snapshot.deckVersion,
            "slides": snapshot.slides
        ]), on: connection)
    }

    private func navigate(_ request: HTTPRequest, on connection: NWConnection) {
        guard let object = try? JSONSerialization.jsonObject(with: request.body),
              let payload = object as? [String: Any] else {
            send(.json(["ok": false, "error": "invalid_json"], status: 400), on: connection)
            return
        }
        let index = payload["index"] as? Int
        let delta = payload["delta"] as? Int
        guard (index == nil) != (delta == nil) else {
            send(
                .json(
                    ["ok": false, "error": "exactly one of index or delta is required"],
                    status: 400
                ),
                on: connection
            )
            return
        }
        guard session.currentSnapshot().total > 0 else {
            send(.json(["ok": false, "error": "no_deck"], status: 409), on: connection)
            return
        }
        let changed = index.map(session.navigate(to:)) ?? session.navigate(by: delta ?? 0)
        let snapshot = session.currentSnapshot()
        send(.json([
            "ok": true,
            "changed": changed,
            "version": snapshot.version,
            "index": snapshot.index,
            "total": snapshot.total,
            "mode": "deck"
        ]), on: connection)
    }

    private func openEventStream(_ connection: NWConnection) {
        let response = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Content-Security-Policy: \(Self.contentSecurityPolicy)",
            "X-Content-Type-Options: nosniff",
            "",
            ": connected",
            ""
        ].joined(separator: "\r\n")
        let id = ObjectIdentifier(connection)
        eventConnections[id] = connection
        connection.send(content: Data(response.utf8), isComplete: false, completion: .contentProcessed {
            [weak connection] error in
            if error != nil {
                connection?.cancel()
            }
        })
    }

    private func broadcast(version: Int64) {
        queue.async { [weak self] in
            guard let self else { return }
            let payload = Data("data: \(version)\n\n".utf8)
            for (id, connection) in self.eventConnections {
                connection.send(content: payload, isComplete: false, completion: .contentProcessed {
                    [weak self, weak connection] error in
                    guard error != nil, let self, let connection else { return }
                    self.queue.async {
                        self.eventConnections.removeValue(forKey: id)
                        self.connections.removeValue(forKey: id)
                        connection.cancel()
                    }
                })
            }
        }
    }

    private func sendDeckAsset(_ relativePath: String, on connection: NWConnection) {
        let snapshot = session.currentSnapshot()
        guard let sourceURL = snapshot.sourceURL, let workspaceRoot = snapshot.workspaceRoot else {
            send(.text("Not found.", status: 404), on: connection)
            return
        }
        let roots = [
            sourceURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true),
            workspaceRoot.appendingPathComponent("assets", isDirectory: true)
        ]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            if let file = PathSecurity.resolveFile(in: root, relativePath: relativePath) {
                sendFile(file, on: connection)
                return
            }
        }
        send(.text("Not found.", status: 404), on: connection)
    }

    private func sendThemeAsset(_ relativePath: String, on connection: NWConnection) {
        guard let root = session.currentSnapshot().theme.assetRoot,
              let file = PathSecurity.resolveFile(in: root, relativePath: relativePath) else {
            send(.text("Not found.", status: 404), on: connection)
            return
        }
        sendFile(file, on: connection)
    }

    private func sendExportData(on connection: NWConnection) {
        let snapshot = session.currentSnapshot()
        let customThemeMeta = snapshot.theme.metadataJSON.isEmpty
            ? NSNull()
            : (try? JSONSerialization.jsonObject(
                with: Data(snapshot.theme.metadataJSON.utf8)
            )) ?? NSNull()
        send(.json([
            "slides": snapshot.slides,
            "theme": snapshot.theme.name,
            "customThemeCss": snapshot.theme.css,
            "customThemeMeta": customThemeMeta,
            "themeLocked": false
        ]), on: connection)
    }

    private func sendStatic(root: URL, relativePath: String, on connection: NWConnection) {
        guard let file = PathSecurity.resolveFile(in: root, relativePath: relativePath) else {
            send(.text("Not found.", status: 404), on: connection)
            return
        }
        sendFile(file, on: connection)
    }

    private func sendFile(_ url: URL, on connection: NWConnection) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            send(.text("Not found.", status: 404), on: connection)
            return
        }
        send(.data(data, contentType: Self.mimeType(for: url)), on: connection)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let headers = [
            "HTTP/1.1 \(response.status) \(Self.reasonPhrase(for: response.status))",
            "Content-Type: \(response.contentType)",
            "Content-Length: \(response.body.count)",
            "Cache-Control: no-store",
            "Content-Security-Policy: \(Self.contentSecurityPolicy)",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
            "",
            ""
        ]
        var payload = Data(headers.joined(separator: "\r\n").utf8)
        payload.append(response.body)
        connection.send(content: payload, isComplete: true, completion: .contentProcessed {
            [weak connection] _ in
            connection?.cancel()
        })
    }

    private static let contentSecurityPolicy =
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " +
        "script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'"

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "avif": "image/avif"
        case "ico": "image/x-icon"
        default: "application/octet-stream"
        }
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Response"
        }
    }
}

private final class ListenerStartState: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private(set) var result: Result<UInt16, Error>?

    func finish(_ result: Result<UInt16, Error>) {
        let shouldSignal = lock.withLock {
            guard self.result == nil else { return false }
            self.result = result
            return true
        }
        if shouldSignal {
            semaphore.signal()
        }
    }
}

private struct HTTPRequest: Sendable {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerRange.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= contentLength else {
            return nil
        }
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        return HTTPRequest(
            method: parts[0].uppercased(),
            target: parts[1],
            headers: headers,
            body: Data(data[bodyStart..<bodyEnd])
        )
    }
}

private struct HTTPResponse: Sendable {
    let status: Int
    let contentType: String
    let body: Data

    static func text(_ value: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(value.utf8))
    }

    static func data(_ value: Data, contentType: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: contentType, body: value)
    }

    static func json(_ value: [String: Any], status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }
}

private extension URLComponents {
    func queryItem(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
