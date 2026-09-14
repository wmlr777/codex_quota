import Foundation

struct QuotaWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int? { usedPercent.map { Int(max(0, min(100, 100 - $0)).rounded()) } }
    var label: String {
        guard let minutes = windowDurationMins else { return L10n.text("额度窗口", "Quota window") }
        if minutes % 10080 == 0 { return L10n.text("\(minutes / 10080) 周", "\(minutes / 10080) wk") }
        if minutes % 1440 == 0 { return L10n.text("\(minutes / 1440) 天", "\(minutes / 1440) d") }
        if minutes % 60 == 0 { return L10n.text("\(minutes / 60) 小时", "\(minutes / 60) hr") }
        return L10n.text("\(minutes) 分钟", "\(minutes) min")
    }
}
struct QuotaBucket: Decodable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
}
struct QuotaResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var codex: QuotaBucket? {
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty { return buckets["codex"] }
        return rateLimits
    }
}

enum QuotaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

// All state and callbacks are confined to the main queue. No credentials are read or logged.
final class QuotaClient {
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var completion: ((Result<QuotaBucket, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var generation = UUID()

    static func executable() -> String? {
        let defaults = UserDefaults.standard.string(forKey: "codexPath")
        let candidates = [ProcessInfo.processInfo.environment["CODEX_BIN"], defaults,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return (candidates.compactMap { $0 } + pathCandidates).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch(_ callback: @escaping (Result<QuotaBucket, Error>) -> Void) {
        guard completion == nil else { return }
        guard let executable = Self.executable() else {
            callback(.failure(QuotaError.message(L10n.text("找不到 Codex，请安装 Codex 或选择可执行文件。", "Codex was not found. Install Codex or select its executable.")))); return
        }
        completion = callback
        generation = UUID()
        let token = generation
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = ["app-server"]
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        process = p; input = stdin; output = stdout; buffer = Data()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if !data.isEmpty { self.receive(data) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self, self.generation == token, self.completion != nil else { return }
                self.finish(.failure(QuotaError.message(L10n.text("Codex 连接已退出，请检查登录状态后重试。", "The Codex connection closed. Check your sign-in and try again."))))
            }
        }
        do {
            try p.run()
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_quota", "title": "Codex Quota", "version": "1.0.1"]]])
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.generation == token else { return }
                self.finish(.failure(QuotaError.message(L10n.text("读取超时，请检查网络和 Codex 登录状态。", "The request timed out. Check your network and Codex sign-in."))))
            }
            timeout = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)
        } catch { finish(.failure(error)) }
    }
    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        try input?.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 4_000_000 else { finish(.failure(QuotaError.message(L10n.text("Codex 返回的数据过大。", "The Codex response was too large.")))); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            if object["error"] != nil {
                finish(.failure(QuotaError.message(L10n.text("无法读取额度，请在 Codex 中使用 ChatGPT 账号登录后重试。", "Cannot read quota. Sign in to Codex with your ChatGPT account and try again.")))); return
            }
            do {
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = object["result"] {
                    let decoded = try JSONDecoder().decode(QuotaResponse.self, from: JSONSerialization.data(withJSONObject: result))
                    guard let bucket = decoded.codex else { throw QuotaError.message(L10n.text("当前账号未返回 Codex 额度。", "No Codex quota was returned for this account.")) }
                    finish(.success(bucket)); return
                }
            } catch { finish(.failure(error)); return }
        }
    }
    private func finish(_ result: Result<QuotaBucket, Error>) {
        let callback = completion; completion = nil
        stop(); callback?(result)
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let p = process, p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        }
        process = nil; input = nil; output = nil
    }
}
