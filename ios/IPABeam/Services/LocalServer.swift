import Foundation
import Network
import Security

/// Tiny HTTP(S) server bound to the loopback interface only.
/// Serves a fixed set of routes (manifest, IPA, configuration profile, health check).
final class LocalServer: @unchecked Sendable {
    struct Route {
        var contentType: String
        var body: Body

        enum Body {
            case data(Data)
            case file(URL)
        }
    }

    enum ServerError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): return "Lokaler Server: \(message)"
            }
        }
    }

    private let queue = DispatchQueue(label: "app.ipabeam.localserver")
    private let identity: SecIdentity?
    private var listener: NWListener?
    private var routes: [String: Route] = [:]
    private(set) var port: UInt16 = 0

    init(identity: SecIdentity?) {
        self.identity = identity
    }

    var isRunning: Bool { listener != nil && port != 0 }

    func setRoute(_ path: String, _ route: Route) {
        queue.sync { routes[path] = route }
    }

    func start() async throws -> UInt16 {
        if isRunning { return port }

        let tcp = NWProtocolTCP.Options()
        let parameters: NWParameters
        if let identity {
            let tls = NWProtocolTLS.Options()
            guard let secIdentity = sec_identity_create(identity) else {
                throw ServerError.failed("TLS-Identität ungültig")
            }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            parameters = NWParameters(tls: tls, tcp: tcp)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    let port = listener.port?.rawValue ?? 0
                    self?.port = port
                    continuation.resume(returning: port)
                case .failed(let error):
                    resumed = true
                    self?.listener = nil
                    continuation.resume(throwing: ServerError.failed(error.localizedDescription))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(to: header, on: connection)
            } else if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let requestLine = header.split(separator: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        var path = parts.count > 1 ? String(parts[1]) : "/"
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }

        guard let route = routes[path] else {
            send(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8), on: connection)
            return
        }

        switch route.body {
        case .data(let data):
            send(status: "200 OK", contentType: route.contentType, body: method == "HEAD" ? nil : data,
                 length: data.count, on: connection)
        case .file(let url):
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
                send(status: "404 Not Found", contentType: "text/plain", body: Data("Missing".utf8), on: connection)
                return
            }
            let head = responseHeader(status: "200 OK", contentType: route.contentType, length: size)
            connection.send(content: head, completion: .contentProcessed { [weak self] error in
                guard error == nil, method != "HEAD" else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                self?.stream(handle, on: connection)
            })
        }
    }

    private func stream(_ handle: FileHandle, on connection: NWConnection) {
        let chunk = handle.readData(ofLength: 512 * 1024)
        if chunk.isEmpty {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? handle.close()
                connection.cancel()
            } else {
                self?.stream(handle, on: connection)
            }
        })
    }

    private func responseHeader(status: String, contentType: String, length: Int) -> Data {
        Data((
            "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(length)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"
        ).utf8)
    }

    private func send(status: String, contentType: String, body: Data?, length: Int? = nil, on connection: NWConnection) {
        var payload = responseHeader(status: status, contentType: contentType, length: length ?? body?.count ?? 0)
        if let body { payload.append(body) }
        connection.send(content: payload, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }
}
