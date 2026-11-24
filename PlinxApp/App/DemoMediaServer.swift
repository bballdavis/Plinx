import Foundation
import Network

/// Serves bundled, original samples to the production HTTP playback/download
/// clients. The listener binds only to loopback, never the LAN or Internet.
// All mutable state is confined to queue, including Network callbacks.
final class DemoMediaServer: @unchecked Sendable {
    static let shared = DemoMediaServer()
    private let queue = DispatchQueue(label: "plinx.demo.http")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var baseURL: URL?

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let baseURL = self.baseURL {
                    continuation.resume(returning: baseURL)
                    return
                }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    var pending: CheckedContinuation<URL, Error>? = continuation
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard let port = listener.port,
                                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else { return }
                            self.baseURL = url
                            pending?.resume(returning: url)
                            pending = nil
                        case .failed(let error):
                            pending?.resume(throwing: error)
                            pending = nil
                            self.stopOnQueue()
                        case .cancelled:
                            pending?.resume(throwing: URLError(.cancelled))
                            pending = nil
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { connection in
                        guard self.connections.count < 32 else { connection.cancel(); return }
                        let id = UUID()
                        self.connections[id] = connection
                        connection.stateUpdateHandler = { state in
                            if case .failed = state { self.close(id) }
                            if case .cancelled = state { self.connections[id] = nil }
                        }
                        connection.start(queue: self.queue)
                        self.receive(connection, id: id, buffer: Data())
                        self.queue.asyncAfter(deadline: .now() + 15) { self.close(id) }
                    }
                    listener.start(queue: self.queue)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        baseURL = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 65_536 else { self.close(id); return }
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)),
               let head = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) {
                let length = head.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                guard length >= 0, length <= 32_768 else { self.close(id); return }
                if buffer.count >= boundary.upperBound + length {
                    self.respond(connection, id: id, header: buffer)
                } else if complete || error != nil {
                    self.close(id)
                } else {
                    self.receive(connection, id: id, buffer: buffer)
                }
            } else if complete || error != nil {
                self.close(id)
            } else {
                self.receive(connection, id: id, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, id: UUID, header: Data) {
        guard let baseURL, let text = String(data: header, encoding: .utf8) else { close(id); return }
        guard let boundary = text.range(of: "\r\n\r\n") else { close(id); return }
        let lines = String(text[..<boundary.lowerBound]).components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count == 3, first[1].hasPrefix("/"), !first[1].hasPrefix("//"),
              let url = URL(string: String(first[1]), relativeTo: baseURL)?.absoluteURL,
              url.host == "127.0.0.1" else { close(id); return }
        var request = URLRequest(url: url)
        request.httpMethod = String(first[0])
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            request.setValue(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces),
                             forHTTPHeaderField: String(line[..<colon]))
        }
        if let boundary = header.range(of: Data("\r\n\r\n".utf8)) {
            request.httpBody = header.subdata(in: boundary.upperBound..<header.count)
        }
        let response = DemoFixtureCatalog.response(for: request)
        let payload = DemoHTTPResponse.encode(response, request: request)
        connection.send(content: payload, completion: .contentProcessed { _ in self.close(id) })
    }
}

enum DemoHTTPResponse {
    /// AV/FFmpeg clients seek with byte ranges; downloads use the same bytes
    /// without a Range header. Invalid or multipart ranges fail closed.
    static func encode(_ response: DemoFixtureResponse, request: URLRequest) -> Data {
        var status = response.statusCode
        var body = response.data
        var headers = ["Content-Type": response.mimeType, "Cache-Control": "no-store", "Connection": "close"]
        if response.mimeType == "video/mp4", status == 200 {
            headers["Accept-Ranges"] = "bytes"
            if let range = request.value(forHTTPHeaderField: "Range") {
                if let bounds = byteRange(range, count: body.count) {
                    headers["Content-Range"] = "bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(body.count)"
                    body = body.subdata(in: bounds.lowerBound..<(bounds.upperBound + 1))
                    status = 206
                } else {
                    headers["Content-Range"] = "bytes */\(body.count)"
                    body = Data()
                    status = 416
                }
            }
        }
        headers["Content-Length"] = String(body.count)
        let reason = [200: "OK", 206: "Partial Content", 400: "Bad Request", 404: "Not Found", 416: "Range Not Satisfiable"][status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\n" + headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        var result = Data(head.utf8)
        if request.httpMethod != "HEAD" { result.append(body) }
        return result
    }

    static func byteRange(_ value: String, count: Int) -> ClosedRange<Int>? {
        guard count > 0, value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            return max(0, count - suffix)...(count - 1)
        }
        guard let start = Int(parts[0]), start >= 0, start < count else { return nil }
        let end: Int
        if parts[1].isEmpty { end = count - 1 }
        else {
            guard let requestedEnd = Int(parts[1]), requestedEnd >= start else { return nil }
            end = min(requestedEnd, count - 1)
        }
        return start...end
    }
}
