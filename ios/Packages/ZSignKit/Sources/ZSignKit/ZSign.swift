import CZSign
import Foundation

/// Swift wrapper around zsign (compiled into the app) and the local CA generator.
public enum ZSign {
    public struct Options: Sendable {
        public var p12: URL
        public var password: String
        public var profile: URL
        public var bundleID: String?
        public var removeExtensions: Bool

        public init(p12: URL, password: String, profile: URL, bundleID: String? = nil, removeExtensions: Bool = true) {
            self.p12 = p12
            self.password = password
            self.profile = profile
            self.bundleID = bundleID
            self.removeExtensions = removeExtensions
        }
    }

    public struct Output: Sendable {
        public let success: Bool
        public let log: String
    }

    public enum Failure: LocalizedError {
        case localCA(String)

        public var errorDescription: String? {
            switch self {
            case .localCA(let message): return "Lokales Zertifikat: \(message)"
            }
        }
    }

    /// zsign uses process-wide state (getopt, stdout), so only one run at a time.
    private static let lock = NSLock()

    /// Signs `ipa` and writes the result to `output`. Blocking – call from a background task.
    public static func sign(ipa: URL, output: URL, options: Options, workDirectory: URL) -> Output {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: output)

        var arguments = [
            "zsign",
            "-k", options.p12.path,
            "-p", options.password,
            "-m", options.profile.path,
            "-o", output.path,
            "-z", "1",
            "-t", workDirectory.path
        ]
        if let bundleID = options.bundleID, !bundleID.isEmpty {
            arguments += ["-b", bundleID]
        }
        if options.removeExtensions {
            arguments += ["-E", "-W"]
        }
        arguments.append(ipa.path)

        // Capture zsign's console output into a log file.
        let logURL = workDirectory.appendingPathComponent("zsign.log")
        fflush(stdout)
        fflush(stderr)
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        let logFD = open(logURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if logFD >= 0 {
            dup2(logFD, STDOUT_FILENO)
            dup2(logFD, STDERR_FILENO)
        }

        let previousDirectory = fileManager.currentDirectoryPath
        fileManager.changeCurrentDirectoryPath(workDirectory.path)

        var cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        cArguments.append(nil)
        czsign_reset_getopt()
        let code = zsign_main(Int32(arguments.count), &cArguments)
        cArguments.forEach { free($0) }

        fileManager.changeCurrentDirectoryPath(previousDirectory)
        fflush(stdout)
        fflush(stderr)
        if logFD >= 0 {
            dup2(savedOut, STDOUT_FILENO)
            dup2(savedErr, STDERR_FILENO)
            close(logFD)
        }
        close(savedOut)
        close(savedErr)

        var log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if !options.password.isEmpty {
            log = log.replacingOccurrences(of: options.password, with: "••••")
        }
        let success = code == 0 && fileManager.fileExists(atPath: output.path)
        return Output(success: success, log: log)
    }

    /// Creates a new local CA certificate (DER) and server identity (PKCS#12).
    public static func makeLocalCA(caCertificate: URL, serverIdentity: URL, password: String) throws {
        var buffer = [CChar](repeating: 0, count: 512)
        let result = czsign_make_local_ca(caCertificate.path, serverIdentity.path, password, &buffer, Int32(buffer.count))
        if result != 0 {
            throw Failure.localCA(String(cString: buffer))
        }
    }
}
