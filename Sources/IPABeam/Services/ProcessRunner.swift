import Foundation

/// Result of a finished command line process.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data

    var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
    var stderr: String { String(decoding: stderrData, as: UTF8.self) }
    var succeeded: Bool { exitCode == 0 }

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum ProcessError: LocalizedError {
    case toolMissing(String)
    case launchFailed(String, String)
    case failed(tool: String, code: Int32, output: String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            return "Das Werkzeug „\(name)“ wurde nicht gefunden."
        case .launchFailed(let name, let reason):
            return "„\(name)“ konnte nicht gestartet werden: \(reason)"
        case .failed(let tool, let code, let output):
            let detail = output
                .split(separator: "\n")
                .suffix(8)
                .joined(separator: "\n")
            return detail.isEmpty
                ? "„\(tool)“ ist fehlgeschlagen (Code \(code))."
                : "„\(tool)“ ist fehlgeschlagen (Code \(code)):\n\(detail)"
        case .timedOut(let name):
            return "„\(name)“ hat nicht rechtzeitig geantwortet."
        }
    }
}

/// Thread-safe collector that keeps the complete output and optionally
/// forwards every complete line to a callback (used for live logs & progress).
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        var lines: [String] = []
        lock.lock()
        data.append(chunk)
        if onLine != nil {
            pending.append(chunk)
            while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let lineData = pending[pending.startIndex..<index]
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { lines.append(line) }
                pending.removeSubrange(pending.startIndex...index)
            }
        }
        lock.unlock()
        if let onLine {
            lines.forEach(onLine)
        }
    }

    func finish() -> Data {
        lock.lock()
        let rest = pending
        pending = Data()
        let all = data
        lock.unlock()
        if let onLine, !rest.isEmpty {
            let line = String(decoding: rest, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { onLine(line) }
        }
        return all
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var _timedOut = false

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return _timedOut
    }

    func terminate(becauseOfTimeout: Bool = false) {
        lock.lock()
        if becauseOfTimeout { _timedOut = true }
        lock.unlock()
        if process.isRunning { process.terminate() }
    }
}

enum ProcessRunner {
    /// Additional directories where Homebrew & friends install their tools.
    static let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin"]

    static var environmentPath: String {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var parts = extraPaths
        let systemParts = current.split(separator: ":").map(String.init) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for part in systemParts where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: ":")
    }

    /// Finds an executable by name in PATH + Homebrew locations.
    static func locate(_ name: String) -> URL? {
        for directory in environmentPath.split(separator: ":") {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Runs a process asynchronously. Supports live line output, timeouts and Task cancellation.
    @discardableResult
    static func run(
        _ executable: URL,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        name: String? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let toolName = name ?? executable.lastPathComponent
        let box = ProcessBox()

        let result: ProcessResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let process = box.process
                process.executableURL = executable
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = environmentPath
                process.environment = environment
                if let currentDirectory {
                    process.currentDirectoryURL = currentDirectory
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                let outCollector = OutputCollector(onLine: onLine)
                let errCollector = OutputCollector(onLine: onLine)

                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        outCollector.append(chunk)
                    }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        errCollector.append(chunk)
                    }
                }

                process.terminationHandler = { finished in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    outCollector.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                    errCollector.append(errPipe.fileHandleForReading.readDataToEndOfFile())

                    let result = ProcessResult(
                        exitCode: finished.terminationStatus,
                        stdoutData: outCollector.finish(),
                        stderrData: errCollector.finish()
                    )
                    if box.timedOut {
                        continuation.resume(throwing: ProcessError.timedOut(toolName))
                    } else {
                        continuation.resume(returning: result)
                    }
                }

                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ProcessError.launchFailed(toolName, error.localizedDescription))
                    return
                }

                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        box.terminate(becauseOfTimeout: true)
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        return result
    }

    /// Like `run`, but throws if the process exits with a non-zero code.
    @discardableResult
    static func runChecked(
        _ executable: URL,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        name: String? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let toolName = name ?? executable.lastPathComponent
        let result = try await run(
            executable,
            arguments,
            currentDirectory: currentDirectory,
            timeout: timeout,
            name: toolName,
            onLine: onLine
        )
        guard result.succeeded else {
            throw ProcessError.failed(tool: toolName, code: result.exitCode, output: result.combinedOutput)
        }
        return result
    }
}

enum SystemTool {
    static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
    static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
    static let zip = URL(fileURLWithPath: "/usr/bin/zip")
    static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    static let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
    static let security = URL(fileURLWithPath: "/usr/bin/security")
}

enum TextMatching {
    /// Returns the capture groups of the first regex match, or nil.
    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: index), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    /// Extracts a percentage like "42%" or "(42%)" from a tool output line.
    static func percent(in line: String) -> Double? {
        guard let groups = firstMatch(#"(\d{1,3}(?:\.\d+)?)\s?%"#, in: line),
              groups.count > 1,
              let value = Double(groups[1]) else { return nil }
        return min(max(value / 100, 0), 1)
    }
}
