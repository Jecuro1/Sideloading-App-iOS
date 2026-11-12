import Foundation
import Observation

struct LogLine: Identifiable, Sendable {
    enum Kind: Sendable { case info, step, success, error }
    let id = UUID()
    let date = Date()
    let text: String
    let kind: Kind
}

/// A single installation run with its steps, progress and log.
@MainActor
@Observable
final class InstallJob: Identifiable {
    enum Step: String, CaseIterable, Identifiable {
        case prepare
        case sign
        case install

        var id: String { rawValue }

        var title: String {
            switch self {
            case .prepare: return "Vorbereiten"
            case .sign: return "Signieren"
            case .install: return "Übertragen & installieren"
            }
        }

        var symbol: String {
            switch self {
            case .prepare: return "shippingbox"
            case .sign: return "signature"
            case .install: return "arrow.down.to.line.compact"
            }
        }

        var weight: Double {
            switch self {
            case .prepare: return 0.15
            case .sign: return 0.20
            case .install: return 0.65
            }
        }
    }

    enum StepState: Equatable {
        case pending, running, done, skipped, failed
    }

    enum State: Equatable {
        case running
        case succeeded
        case failed(String)
        case cancelled

        var isFinished: Bool { self != .running }
    }

    let id = UUID()
    let appName: String
    let bundleID: String
    let deviceName: String
    let connection: ConnectionType
    let startedAt = Date()

    private(set) var stepStates: [Step: StepState] = [:]
    private(set) var state: State = .running
    private(set) var log: [LogLine] = []
    private(set) var finishedAt: Date?
    var installProgress: Double = 0
    var finalBundleID: String?

    init(appName: String, bundleID: String, deviceName: String, connection: ConnectionType) {
        self.appName = appName
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.connection = connection
        for step in Step.allCases { stepStates[step] = .pending }
    }

    func state(of step: Step) -> StepState { stepStates[step] ?? .pending }

    var currentStep: Step? {
        Step.allCases.first { stepStates[$0] == .running }
    }

    var overallProgress: Double {
        if state == .succeeded { return 1 }
        var total = 0.0
        for step in Step.allCases {
            switch state(of: step) {
            case .done, .skipped: total += step.weight
            case .running:
                total += step == .install ? step.weight * installProgress : step.weight * 0.5
            case .pending, .failed: break
            }
        }
        return min(total, 0.99)
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func begin(_ step: Step) {
        stepStates[step] = .running
        append(step.title, kind: .step)
    }

    func complete(_ step: Step) {
        stepStates[step] = .done
    }

    func skip(_ step: Step) {
        stepStates[step] = .skipped
    }

    func succeed() {
        for step in Step.allCases where stepStates[step] == .running { stepStates[step] = .done }
        installProgress = 1
        state = .succeeded
        finishedAt = Date()
        append("\(appName) wurde erfolgreich auf \(deviceName) installiert.", kind: .success)
    }

    func fail(_ message: String) {
        for step in Step.allCases where stepStates[step] == .running { stepStates[step] = .failed }
        state = .failed(message)
        finishedAt = Date()
        append(message, kind: .error)
    }

    func cancel() {
        for step in Step.allCases where stepStates[step] == .running { stepStates[step] = .failed }
        state = .cancelled
        finishedAt = Date()
        append("Installation abgebrochen.", kind: .error)
    }

    func append(_ text: String, kind: LogLine.Kind = .info) {
        log.append(LogLine(text: text, kind: kind))
        if log.count > 2_000 {
            log.removeFirst(log.count - 2_000)
        }
    }
}
