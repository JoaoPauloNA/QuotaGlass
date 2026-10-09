import AppKit
import Foundation

/// One official app-server process per isolated local account profile.
@MainActor final class CodexConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var waiting: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    var onLogin: (() -> Void)?

    init(profile: UUID, root: URL, executable: URL) throws {
        let home = root.appendingPathComponent(profile.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"keyring\""]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        // Do not allow shell API keys to replace the user's subscription login.
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "OPENAI_BASE_URL")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor in self?.receive(bytes) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.failPending() }
        }
        try process.run()
    }

    func initialize() async throws {
        _ = try await request("initialize", params: ["clientInfo": ["name": "quotaglass", "title": "QuotaGlass", "version": "0.1.0"]])
        try send(["method": "initialized"])
    }
    func request(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard process.isRunning else { throw ConnectionError.unavailable }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            do {
                var packet: [String: Any] = ["id": id, "method": method]
                if let params { packet["params"] = params }
                try send(packet)
            } catch { waiting.removeValue(forKey: id)?.resume(throwing: error) }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.waiting.removeValue(forKey: id)?.resume(throwing: ConnectionError.timeout)
            }
        }
    }
    private func send(_ packet: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: packet)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ bytes: Data) {
        guard !bytes.isEmpty else { failPending(); return }
        buffer.append(bytes)
        guard buffer.count < 2_000_000 else { stop(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]
            buffer.removeSubrange(...end)
            guard let packet = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = packet["id"] as? Int, let continuation = waiting.removeValue(forKey: id) {
                if packet["error"] != nil { continuation.resume(throwing: ConnectionError.requestFailed) }
                else { continuation.resume(returning: packet["result"] as? [String: Any] ?? [:]) }
            } else if packet["method"] as? String == "account/login/completed" {
                onLogin?()
            }
        }
    }
    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        failPending()
    }
    private func failPending() {
        let pending = Array(waiting.values)
        waiting.removeAll()
        for continuation in pending { continuation.resume(throwing: ConnectionError.unavailable) }
    }
    enum ConnectionError: LocalizedError {
        case unavailable, timeout, requestFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Codex indisponível. Instale o CLI oficial ou confira seu caminho nas configurações."
            case .timeout: return "A consulta do Codex demorou demais. Tente novamente."
            case .requestFailed: return "Não foi possível consultar a conta. Reconecte pelo aplicativo."
            }
        }
    }
}
