import Foundation

// MARK: - Tool detection

struct ToolStatus: Equatable, Sendable {
    var checked = false
    var devicectl = false
    var ideviceID: URL?
    var ideviceInfo: URL?
    var ideviceInstaller: URL?
    var idevicePair: URL?

    var libimobiledeviceReady: Bool {
        ideviceID != nil && ideviceInfo != nil && ideviceInstaller != nil
    }

    var hasAnyBackend: Bool { devicectl || libimobiledeviceReady }

    static func detect() async -> ToolStatus {
        var status = ToolStatus(checked: true)
        status.devicectl = await DevicectlClient.isAvailable()
        status.ideviceID = ProcessRunner.locate("idevice_id")
        status.ideviceInfo = ProcessRunner.locate("ideviceinfo")
        status.ideviceInstaller = ProcessRunner.locate("ideviceinstaller")
        status.idevicePair = ProcessRunner.locate("idevicepair")
        return status
    }
}

// MARK: - Apple devicectl (Xcode 15+)

enum DevicectlClient {
    static func isAvailable() async -> Bool {
        guard let result = try? await ProcessRunner.run(
            SystemTool.xcrun, ["--find", "devicectl"], timeout: 20, name: "xcrun"
        ) else { return false }
        return result.succeeded
    }

    static func listDevices() async throws -> [Device] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipabeam-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await ProcessRunner.run(
            SystemTool.xcrun,
            ["devicectl", "list", "devices", "--json-output", output.path],
            timeout: 40,
            name: "devicectl"
        )
        guard result.succeeded, let data = try? Data(contentsOf: output) else {
            throw ProcessError.failed(tool: "devicectl", code: result.exitCode, output: result.combinedOutput)
        }
        return parseDevices(data)
    }

    static func parseDevices(_ data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entries = result["devices"] as? [[String: Any]] else { return [] }

        return entries.compactMap { entry -> Device? in
            guard let identifier = entry["identifier"] as? String else { return nil }
            let deviceProps = entry["deviceProperties"] as? [String: Any] ?? [:]
            let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]

            let platform = (hardware["platform"] as? String ?? "").lowercased()
            guard platform.isEmpty || platform == "ios" || platform == "ipados" else { return nil }

            let transport = connection["transportType"] as? String
            let tunnel = connection["tunnelState"] as? String
            let pairing = connection["pairingState"] as? String

            var connectionType: ConnectionType
            switch transport {
            case "wired": connectionType = .usb
            case "localNetwork", "network": connectionType = .wifi
            default: connectionType = .offline
            }
            if tunnel == "unavailable" { connectionType = .offline }

            let productType = hardware["productType"] as? String ?? ""
            let model = (hardware["marketingName"] as? String)
                ?? DeviceNames.marketingName(for: productType)

            var device = Device(
                id: identifier,
                udid: hardware["udid"] as? String,
                name: deviceProps["name"] as? String ?? model,
                model: model,
                osVersion: deviceProps["osVersionNumber"] as? String ?? "",
                deviceClass: hardware["deviceType"] as? String ?? "iPhone",
                connection: connectionType,
                backend: .devicectl
            )
            device.needsTrust = pairing != nil && pairing != "paired"
            device.developerModeEnabled = deviceProps["developerModeStatus"].map { ($0 as? String) == "enabled" }
            return device
        }
    }

    static func install(
        appAt url: URL,
        on device: Device,
        progress: @escaping @Sendable (Double) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        let result = try await ProcessRunner.run(
            SystemTool.xcrun,
            ["devicectl", "device", "install", "app", "--device", device.id, url.path],
            name: "devicectl"
        ) { line in
            log(line)
            if let value = TextMatching.percent(in: line) { progress(value) }
        }
        guard result.succeeded else {
            throw ProcessError.failed(tool: "devicectl", code: result.exitCode, output: result.combinedOutput)
        }
        progress(1)
    }
}

// MARK: - libimobiledevice (Homebrew)

enum LibimobiledeviceClient {
    static func listDevices(tools: ToolStatus) async -> [Device] {
        guard let ideviceID = tools.ideviceID else { return [] }
        var entries: [(String, ConnectionType)] = []

        if let usb = try? await ProcessRunner.run(ideviceID, ["-l"], timeout: 10), usb.succeeded {
            for udid in lines(of: usb.stdout) {
                entries.append((udid, .usb))
            }
        }
        if let network = try? await ProcessRunner.run(ideviceID, ["-n"], timeout: 10), network.succeeded {
            for udid in lines(of: network.stdout) where !entries.contains(where: { $0.0 == udid }) {
                entries.append((udid, .wifi))
            }
        }

        var devices: [Device] = []
        for (udid, connection) in entries {
            devices.append(await describe(udid: udid, connection: connection, tools: tools))
        }
        return devices
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { $0.split(separator: " ").first.map(String.init) }
            .filter { !$0.isEmpty }
    }

    private static func describe(udid: String, connection: ConnectionType, tools: ToolStatus) async -> Device {
        var device = Device(
            id: udid,
            udid: udid,
            name: "iPhone",
            model: "",
            osVersion: "",
            deviceClass: "iPhone",
            connection: connection,
            backend: .libimobiledevice
        )
        guard let ideviceInfo = tools.ideviceInfo else { return device }

        var args = ["-u", udid]
        if connection == .wifi { args.append("-n") }

        guard let result = try? await ProcessRunner.run(ideviceInfo, args, timeout: 12) else {
            device.connection = .offline
            return device
        }
        guard result.succeeded else {
            device.needsTrust = true
            device.name = "Gerät nicht gekoppelt"
            return device
        }

        var values: [String: String] = [:]
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        device.name = values["DeviceName"] ?? device.name
        device.osVersion = values["ProductVersion"] ?? ""
        device.deviceClass = values["DeviceClass"] ?? "iPhone"
        device.model = DeviceNames.marketingName(for: values["ProductType"] ?? "")
        return device
    }

    static func install(
        ipaAt url: URL,
        on device: Device,
        tools: ToolStatus,
        progress: @escaping @Sendable (Double) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let installer = tools.ideviceInstaller else {
            throw ProcessError.toolMissing("ideviceinstaller")
        }
        var args = ["-u", device.udid ?? device.id]
        if device.connection == .wifi { args.append("-n") }
        args += ["-i", url.path]

        let result = try await ProcessRunner.run(installer, args, name: "ideviceinstaller") { line in
            log(line)
            if let value = TextMatching.percent(in: line) { progress(value) }
        }
        let output = result.combinedOutput
        let reportedError = output.contains("ERROR") && !output.contains("Install: Complete")
        guard result.succeeded, !reportedError else {
            throw ProcessError.failed(tool: "ideviceinstaller", code: result.exitCode, output: output)
        }
        progress(1)
    }

    static func pair(udid: String, tools: ToolStatus) async throws -> String {
        guard let pairTool = tools.idevicePair else { throw ProcessError.toolMissing("idevicepair") }
        let result = try await ProcessRunner.run(pairTool, ["-u", udid, "pair"], timeout: 60)
        guard result.succeeded else {
            throw ProcessError.failed(tool: "idevicepair", code: result.exitCode, output: result.combinedOutput)
        }
        return result.combinedOutput
    }
}

// MARK: - Unified device access

enum DeviceManager {
    static func listDevices(preference: BackendPreference, tools: ToolStatus) async -> (devices: [Device], error: String?) {
        var devices: [Device] = []
        var errors: [String] = []

        let useDevicectl = tools.devicectl && preference != .libimobiledevice
        let useLibimobiledevice = tools.libimobiledeviceReady && preference != .devicectl

        if useDevicectl {
            do {
                devices = try await DevicectlClient.listDevices()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if useLibimobiledevice {
            let libDevices = await LibimobiledeviceClient.listDevices(tools: tools)
            for libDevice in libDevices {
                let key = libDevice.udid?.uppercased()
                if let index = devices.firstIndex(where: { $0.udid?.uppercased() == key && key != nil }) {
                    // Prefer whichever backend currently reaches the device.
                    if !devices[index].isAvailable && libDevice.isAvailable {
                        devices[index] = libDevice
                    }
                } else {
                    devices.append(libDevice)
                }
            }
        }

        devices.sort { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            if lhs.connection != rhs.connection { return lhs.connection == .usb }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return (devices, errors.first)
    }

    /// Installs either an extracted `.app` (devicectl) or an `.ipa` (libimobiledevice).
    static func install(
        _ url: URL,
        on device: Device,
        tools: ToolStatus,
        progress: @escaping @Sendable (Double) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        switch device.backend {
        case .devicectl:
            try await DevicectlClient.install(appAt: url, on: device, progress: progress, log: log)
        case .libimobiledevice:
            try await LibimobiledeviceClient.install(ipaAt: url, on: device, tools: tools, progress: progress, log: log)
        }
    }
}
