import Foundation
import Network
import OSLog

/// Serves the credential-free demo library over HTTP on the loopback interface.
///
/// A real socket (instead of an in-process `URLProtocol`) lets every client
/// the production app uses reach the fixtures: Plex repositories, SwiftUI's
/// private `AsyncImage` session, and the player engine. The listener accepts
/// only loopback connections that present the synthetic demo token, serves only
/// fictional fixture data, and never proxies to another host.
final class DemoFixtureServer: @unchecked Sendable {
    static let shared = DemoFixtureServer()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Plinx", category: "DemoFixtureServer")

    static let loopbackHost = "127.0.0.1"
    static let videoPathPrefix = "/video/"
    static let clipResourceName = "plinx-demo-clip"

    private let queue = DispatchQueue(label: "com.bballdavis.plinx.demo-fixture-server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var boundPort: NWEndpoint.Port?
    private var running = false

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    var baseURL: URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard running, let boundPort else { return nil }
        return URL(string: "http://\(Self.loopbackHost):\(boundPort.rawValue)")
    }

    /// Starts (or reuses) the listener and returns its base URL.
    func start() async throws -> URL {
        if let baseURL { return baseURL }
        let port = try await startListener(on: .any)
        stateLock.lock()
        boundPort = port
        running = true
        stateLock.unlock()
        guard let url = baseURL else { throw URLError(.cannotConnectToHost) }
        return url
    }

    func stop() {
        Self.logger.debug("stop requested")
        stateLock.lock()
        running = false
        boundPort = nil
        let current = listener
        listener = nil
        stateLock.unlock()
        current?.cancel()
    }

    // MARK: - Listener

    private func startListener(on port: NWEndpoint.Port) async throws -> NWEndpoint.Port {
        let parameters = NWParameters.tcp
        // Binding the listener to 127.0.0.1 keeps it unreachable from other
        // devices. (`requiredInterfaceType`/`acceptLocalOnly` are avoided:
        // with an explicit loopback endpoint they make tvOS reset inbound
        // connections before the listener sees them.)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(Self.loopbackHost), port: port)

        let listener = try NWListener(using: parameters)
        stateLock.lock()
        self.listener = listener
        stateLock.unlock()

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    guard !resumed, let port = listener?.port else { return }
                    resumed = true
                    continuation.resume(returning: port)
                case let .failed(error):
                    listener?.cancel()
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    } else {
                        // iOS can reclaim sockets while the app is suspended.
                        // Rebind the same port so the active session's base
                        // URL keeps working when the app returns.
                        self?.restartAfterFailure()
                    }
                case .cancelled:
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func restartAfterFailure() {
        stateLock.lock()
        let port = running ? boundPort : nil
        stateLock.unlock()
        guard let port else { return }
        Task {
            _ = try? await self.startListener(on: port)
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            Self.logger.debug("connection state \(String(describing: state), privacy: .public)")
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }

            Self.logger.debug("received \(data?.count ?? -1) bytes complete=\(isComplete) error=\(String(describing: error), privacy: .public)")
            if let request = DemoHTTPRequest.parse(buffer) {
                Self.logger.debug("request \(request.method, privacy: .public) \(request.path, privacy: .public)")
                let response = self.response(for: request)
                connection.send(content: response.serialized(includeBody: request.method != "HEAD"), completion: .contentProcessed { sendError in
                    if sendError != nil || !request.keepAlive {
                        connection.cancel()
                    } else {
                        self.receiveRequest(on: connection, buffer: Data(buffer.dropFirst(request.consumedLength)))
                    }
                })
                return
            }

            if error != nil || isComplete || buffer.count > 1_048_576 {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func response(for request: DemoHTTPRequest) -> DemoHTTPResponse {
        guard request.token == DemoFixtureBootstrap.serverToken else {
            return DemoHTTPResponse(status: 401, mimeType: "application/json", body: Data(#"{"error":"unauthorized"}"#.utf8))
        }

        if request.path.hasPrefix(Self.videoPathPrefix) {
            return videoResponse(range: request.headers["range"])
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let fixture = DemoFixtureCatalog.response(for: urlRequest)
        return DemoHTTPResponse(status: fixture.statusCode, mimeType: fixture.mimeType, body: fixture.data)
    }

    // MARK: - Video

    private lazy var clipData: Data? = Bundle.main
        .url(forResource: Self.clipResourceName, withExtension: "mp4")
        .flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }

    private func videoResponse(range: String?) -> DemoHTTPResponse {
        guard let clip = clipData else {
            return DemoHTTPResponse(status: 404, mimeType: "application/json", body: Data(#"{"error":"demo clip missing"}"#.utf8))
        }
        guard let range, let bounds = Self.byteRange(range, length: clip.count) else {
            return DemoHTTPResponse(status: 200, mimeType: "video/mp4", body: clip, extraHeaders: ["Accept-Ranges": "bytes"])
        }
        return DemoHTTPResponse(
            status: 206,
            mimeType: "video/mp4",
            body: clip.subdata(in: bounds.lowerBound..<(bounds.upperBound + 1)),
            extraHeaders: [
                "Accept-Ranges": "bytes",
                "Content-Range": "bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(clip.count)",
            ]
        )
    }

    /// Parses a single `bytes=` range into an inclusive byte span.
    static func byteRange(_ header: String, length: Int) -> ClosedRange<Int>? {
        guard length > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 {
            return max(0, length - suffix)...(length - 1)
        }
        guard let start = Int(parts[0]), start < length else { return nil }
        let end = Int(parts[1]).map { min($0, length - 1) } ?? (length - 1)
        return end >= start ? start...end : nil
    }
}

// MARK: - Minimal HTTP/1.1 framing

struct DemoHTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let consumedLength: Int

    var url: URL {
        URL(string: "http://\(DemoFixtureServer.loopbackHost)\(target)") ?? URL(string: "http://\(DemoFixtureServer.loopbackHost)/")!
    }

    var path: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? target
    }

    var token: String? {
        if let header = headers["x-plex-token"] { return header }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value
    }

    var keepAlive: Bool {
        headers["connection"]?.lowercased() != "close"
    }

    /// Returns a request once the header block and any declared body arrived.
    static func parse(_ buffer: Data) -> DemoHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator),
              let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let bodyLength = Int(headers["content-length"] ?? "") ?? 0
        let consumed = (headerEnd.upperBound - buffer.startIndex) + bodyLength
        guard buffer.count >= consumed else { return nil }

        return DemoHTTPRequest(
            method: requestLine[0].uppercased(),
            target: requestLine[1],
            headers: headers,
            consumedLength: consumed
        )
    }
}

struct DemoHTTPResponse {
    let status: Int
    let mimeType: String
    let body: Data
    var extraHeaders: [String: String] = [:]

    func serialized(includeBody: Bool) -> Data {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        head += "Content-Type: \(mimeType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        if includeBody { data.append(body) }
        return data
    }
}
