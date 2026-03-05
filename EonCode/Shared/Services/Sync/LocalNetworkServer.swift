import Foundation
import Network

// MARK: - Local HTTP server (tertiary sync method)
// Mac runs server on port 52731, iOS connects via HTTP
// No third-party dependencies - pure Network.framework

@MainActor
final class LocalNetworkServer: ObservableObject {
    static let shared = LocalNetworkServer()

    @Published var isRunning = false
    @Published var serverURL: URL?
    @Published var connectedClients: [String] = []

    private var listener: NWListener?
    private let port: NWEndpoint.Port = NWEndpoint.Port(rawValue: Constants.Sync.localHTTPPort)!

    private init() {}

    // MARK: - Start server (Mac only)

    func start() {
        #if os(macOS)
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: port) else { return }

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.serverURL = URL(string: "http://localhost:\(Constants.Sync.localHTTPPort)")
                case .failed:
                    self?.isRunning = false
                default: break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        #endif
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURL = nil
    }

    // MARK: - Handle HTTP connection

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let data = data, !data.isEmpty else { return }
            let request = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                let response = await self?.handleHTTPRequest(request) ?? HTTPResponse.notFound()
                self?.sendHTTPResponse(response, over: connection)
            }
        }
    }

    private func handleHTTPRequest(_ raw: String) async -> HTTPResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .badRequest() }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return .badRequest() }

        let method = parts[0]
        let path = parts[1]

        // Parse body (after double CRLF)
        var bodyData: Data? = nil
        if let bodyStart = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[bodyStart.upperBound...])
            bodyData = bodyString.data(using: .utf8)
        }

        switch (method, path) {
        case ("GET", "/status"):
            return await handleStatusRequest()
        case ("GET", "/instructions"):
            return await handleGetInstructions()
        case ("POST", "/instructions"):
            return await handlePostInstruction(body: bodyData)
        case ("GET", let p) where p.hasPrefix("/files/"):
            let filePath = String(p.dropFirst(7))
            return await handleGetFile(path: filePath.removingPercentEncoding ?? filePath)
        case ("PUT", let p) where p.hasPrefix("/files/"):
            let filePath = String(p.dropFirst(7))
            return await handlePutFile(path: filePath.removingPercentEncoding ?? filePath, body: bodyData)
        case ("GET", "/ping"):
            return HTTPResponse(statusCode: 200, body: "{\"pong\":true}".data(using: .utf8)!, contentType: "application/json")
        default:
            return .notFound()
        }
    }

    private func handleStatusRequest() async -> HTTPResponse {
        let status: [String: Any] = [
            "device": UIDevice.deviceName,
            "isMac": UIDevice.isMac,
            "timestamp": Date().iso8601,
            "agentRunning": AgentEngine.shared.isRunning,
            "agentStatus": AgentEngine.shared.statusMessage
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: status) else { return .serverError() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/json")
    }

    private func handleGetInstructions() async -> HTTPResponse {
        let instructions = await InstructionQueue.shared.pendingInstructions()
        guard let data = try? JSONEncoder().encode(instructions) else { return .serverError() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/json")
    }

    private func handlePostInstruction(body: Data?) async -> HTTPResponse {
        guard let body = body,
              let instruction = try? JSONDecoder().decode(Instruction.self, from: body)
        else { return .badRequest() }

        await InstructionQueue.shared.enqueue(instruction)
        return HTTPResponse(statusCode: 201, body: "{\"ok\":true}".data(using: .utf8)!, contentType: "application/json")
    }

    private func handleGetFile(path: String) async -> HTTPResponse {
        guard let root = iCloudSyncEngine.shared.eonCodeRoot else { return .notFound() }
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return .notFound() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/octet-stream")
    }

    private func handlePutFile(path: String, body: Data?) async -> HTTPResponse {
        guard let body = body,
              let root = iCloudSyncEngine.shared.eonCodeRoot
        else { return .badRequest() }

        let url = root.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url)
            return HTTPResponse(statusCode: 200, body: "{\"ok\":true}".data(using: .utf8)!, contentType: "application/json")
        } catch {
            return .serverError()
        }
    }

    // MARK: - Send response

    private func sendHTTPResponse(_ response: HTTPResponse, over connection: NWConnection) {
        var headers = "HTTP/1.1 \(response.statusCode) \(response.statusText)\r\n"
        headers += "Content-Type: \(response.contentType)\r\n"
        headers += "Content-Length: \(response.body.count)\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"

        let headerData = headers.data(using: .utf8) ?? Data()
        let fullData = headerData + response.body

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - iOS Client

final class LocalNetworkClient {
    static let shared = LocalNetworkClient()

    private var macURL: URL?

    func setMacAddress(_ url: URL) {
        macURL = url
    }

    func postInstruction(_ instruction: Instruction) async throws {
        guard let base = macURL else { throw NetworkError.noServerURL }
        var request = URLRequest(url: base.appendingPathComponent("instructions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try instruction.encoded()
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw NetworkError.requestFailed
        }
    }

    func fetchStatus() async throws -> [String: Any] {
        guard let base = macURL else { throw NetworkError.noServerURL }
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("status"))
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func discoverMac() async -> URL? {
        // Try common local addresses
        let candidates = [
            "http://localhost:\(Constants.Sync.localHTTPPort)",
            "http://192.168.1.100:\(Constants.Sync.localHTTPPort)",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate),
               let _ = try? await URLSession.shared.data(from: url.appendingPathComponent("ping")) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Helper types

struct HTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    var statusText: String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(statusCode: 404, body: "{\"error\":\"not found\"}".data(using: .utf8)!, contentType: "application/json")
    }

    static func badRequest() -> HTTPResponse {
        HTTPResponse(statusCode: 400, body: "{\"error\":\"bad request\"}".data(using: .utf8)!, contentType: "application/json")
    }

    static func serverError() -> HTTPResponse {
        HTTPResponse(statusCode: 500, body: "{\"error\":\"server error\"}".data(using: .utf8)!, contentType: "application/json")
    }
}

enum NetworkError: LocalizedError {
    case noServerURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .noServerURL: return "Mac-serverns URL är inte konfigurerad"
        case .requestFailed: return "Nätverksanrop misslyckades"
        }
    }
}
