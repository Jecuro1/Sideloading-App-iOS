import Foundation

/// An app list ("source") in the widely used AltStore/SideStore JSON format.
struct AppSource: Identifiable, Codable, Hashable {
    var id: String { url.absoluteString }
    var url: URL
    var name: String
    var subtitle: String?
    var iconURL: URL?
    var apps: [SourceApp]
    var lastUpdated: Date
}

struct SourceApp: Identifiable, Codable, Hashable {
    var id: String { "\(sourceURL.absoluteString)#\(bundleID)" }
    var sourceURL: URL
    var name: String
    var bundleID: String
    var developer: String
    var subtitle: String?
    var iconURL: URL?
    var iconData: Data?
    var versions: [SourceVersion]

    var latest: SourceVersion? { versions.first }
}

struct SourceVersion: Codable, Hashable {
    var version: String
    var date: String?
    var downloadURL: URL
    var size: Int64?
    var notes: String?
}

enum SourceError: LocalizedError {
    case invalidURL
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Das ist keine gültige Adresse."
        case .invalidFormat: return "Unter dieser Adresse liegt keine gültige App-Quelle (AltStore-Format)."
        }
    }
}

enum SourceLoader {
    static func load(_ url: URL) async throws -> AppSource {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parse(data, url: url)
    }

    static func parse(_ data: Data, url: URL) throws -> AppSource {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawApps = root["apps"] as? [[String: Any]] else {
            throw SourceError.invalidFormat
        }

        let apps: [SourceApp] = rawApps.compactMap { raw in
            guard let bundleID = raw["bundleIdentifier"] as? String,
                  let name = raw["name"] as? String else { return nil }

            var versions: [SourceVersion] = []
            if let list = raw["versions"] as? [[String: Any]] {
                versions = list.compactMap(version(from:))
            }
            if versions.isEmpty, let legacy = version(from: raw) {
                versions = [legacy]
            }
            guard !versions.isEmpty else { return nil }
            versions.sort { isNewer($0.version, than: $1.version) }

            return SourceApp(
                sourceURL: url,
                name: name,
                bundleID: bundleID,
                developer: raw["developerName"] as? String ?? "",
                subtitle: raw["subtitle"] as? String ?? raw["localizedDescription"] as? String,
                iconURL: (raw["iconURL"] as? String).flatMap(URL.init(string:)),
                iconData: nil,
                versions: versions
            )
        }

        return AppSource(
            url: url,
            name: root["name"] as? String ?? url.host ?? "Quelle",
            subtitle: root["subtitle"] as? String ?? root["description"] as? String,
            iconURL: (root["iconURL"] as? String).flatMap(URL.init(string:)),
            apps: apps,
            lastUpdated: Date()
        )
    }

    private static func version(from raw: [String: Any]) -> SourceVersion? {
        guard let version = raw["version"] as? String,
              let urlString = raw["downloadURL"] as? String,
              let url = URL(string: urlString) else { return nil }
        let size = (raw["size"] as? NSNumber)?.int64Value
        return SourceVersion(
            version: version,
            date: raw["date"] as? String ?? raw["versionDate"] as? String,
            downloadURL: url,
            size: size,
            notes: raw["localizedDescription"] as? String ?? raw["versionDescription"] as? String
        )
    }

    /// Numeric version comparison ("1.10" > "1.9").
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }
}

/// Downloads a file and reports progress (0…1).
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let progress: @Sendable (Double) -> Void
    private let destination: URL

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            continuation?.resume(throwing: URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Download fehlgeschlagen (HTTP \(status))."
            ]))
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}
