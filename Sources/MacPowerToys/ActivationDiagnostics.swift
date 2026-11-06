import AppKit
import OSLog

/// A bounded, age-limited local log. All file work stays off the main thread.
final class DiagnosticFileWriter: @unchecked Sendable {
    let directory: URL
    private let queue = DispatchQueue(label: "dev.macpowertoys.diagnostics", qos: .utility)
    private let maximumBytes: Int
    private let retention: TimeInterval
    private var timer: DispatchSourceTimer?
    private let logger = Logger(subsystem: "dev.macpowertoys.app", category: "Activation")

    init(directory: URL, maximumBytes: Int = 262_144, retention: TimeInterval = 86_400) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.retention = retention
        cleanup()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 900, repeating: 900)
        timer.setEventHandler { [weak self] in self?.rewrite(now: Date()) }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    func append(_ record: [String: String], now: Date = Date()) {
        var record = record
        record["recordedAt"] = String(now.timeIntervalSince1970)
        record["timestamp"] = now.ISO8601Format()
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        queue.async { [self] in rewrite(now: now, adding: data) }
    }

    func cleanup(now: Date = Date()) {
        queue.async { [self] in rewrite(now: now) }
    }

    private func rewrite(now: Date, adding newLine: Data? = nil) {
        do {
            let fm = FileManager.default
            let current = directory.appendingPathComponent("activation.jsonl")
            let previous = directory.appendingPathComponent("activation.previous.jsonl")
            var lines: [(time: TimeInterval, data: Data)] = []
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for file in [previous, current] where fm.fileExists(atPath: file.path) {
                for line in try Data(contentsOf: file).split(separator: 0x0a) {
                    guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: String] else { continue }
                    let stamp = record["timestamp"] ?? ""
                    // Older builds wrote fractional UTC timestamps without a Z suffix.
                    let legacyTime = formatter.date(from: stamp)?.timeIntervalSince1970
                        ?? formatter.date(from: stamp + "Z")?.timeIntervalSince1970
                    guard let time = record["recordedAt"].flatMap(Double.init) ?? legacyTime,
                          time > now.timeIntervalSince1970 - retention else { continue }
                    lines.append((time, Data(line)))
                }
            }
            if let newLine { lines.append((now.timeIntervalSince1970, newLine)) }
            lines.sort { $0.time < $1.time }
            var bytes = lines.reduce(0) { $0 + $1.data.count + 1 }
            var start = 0
            while bytes > maximumBytes && start < lines.count {
                bytes -= lines[start].data.count + 1
                start += 1
            }
            let retained = lines.dropFirst(start)
            if retained.isEmpty {
                if fm.fileExists(atPath: current.path) { try fm.removeItem(at: current) }
            } else {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                var output = Data()
                for line in retained { output.append(line.data); output.append(0x0a) }
                try output.write(to: current, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            }
            // Migrate the previous rotation file into the same retention policy.
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
        } catch {
            logger.error("Diagnostic retention/write failed: \(String(describing: error), privacy: .private)")
        }
    }

    func flush() { queue.sync {} }
}

@MainActor
final class ActivationDiagnostics {
    static let shared = ActivationDiagnostics()
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MacPowerToys", isDirectory: true)

    private let writer = DiagnosticFileWriter(directory: directory)
    private var observers: [NSObjectProtocol] = []
    private var trace: (id: String, target: String, start: TimeInterval)?
    private var sampleTask: Task<Void, Never>?
    var statusItemVisible: (() -> Bool)?

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, label) in [
            (NSWorkspace.didActivateApplicationNotification, "workspace.activated"),
            (NSWorkspace.activeSpaceDidChangeNotification, "workspace.spaceChanged")
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let identifier = app?.bundleIdentifier ?? "none"
                Task { @MainActor in
                    guard let self, let trace = self.trace,
                          ProcessInfo.processInfo.systemUptime - trace.start < 3.5 else { return }
                    self.record(label, id: trace.id, target: trace.target, extra: ["eventApp": identifier])
                }
            })
        }
        record("session.started", extra: ["os": ProcessInfo.processInfo.operatingSystemVersionString])
    }

    func begin(target: String, source: String) -> String {
        let id = UUID().uuidString
        sampleTask?.cancel()
        trace = (id, target, ProcessInfo.processInfo.systemUptime)
        record("switch.request", id: id, target: target, extra: ["source": source])
        // Sample changes after the callback as well: callback success is not proof
        // of activation or of the menu bar actually being rendered on screen.
        sampleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self else { return }
            self.record("switch.result", id: id, target: target)
        }
        return id
    }

    func record(_ event: String, id: String? = nil, target: String? = nil, extra: [String: String] = [:]) {
        if event == "switch.openSubmitted" { return }
        if event == "switch.openCompleted", extra["errorCode"] == "0" { return }
        let options = NSApp?.currentSystemPresentationOptions ?? []
        let front = NSWorkspace.shared.frontmostApplication
        let targetApp = target.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first(where: { !$0.isTerminated })
        }
        var fields = extra
        fields["timestamp"] = Date().ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
        fields["uptime"] = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        fields["event"] = event
        fields["request"] = id ?? "none"
        fields["target"] = target ?? "none"
        fields["frontmost"] = front?.bundleIdentifier ?? "none"
        fields["frontmostPID"] = String(front?.processIdentifier ?? 0)
        fields["targetActive"] = String(targetApp?.isActive ?? false)
        fields["targetHidden"] = String(targetApp?.isHidden ?? false)
        fields["selfActive"] = String(NSApp?.isActive ?? false)
        fields["systemPresentationRaw"] = String(options.rawValue)
        fields["hideMenuBar"] = String(options.contains(.hideMenuBar))
        fields["autoHideMenuBar"] = String(options.contains(.autoHideMenuBar))
        fields["fullScreen"] = String(options.contains(.fullScreen))
        fields["menuBarVisible"] = String(NSMenu.menuBarVisible())
        fields["statusItemVisible"] = statusItemVisible.map { String($0()) } ?? "unknown"
        fields["modifierFlags"] = String(NSEvent.modifierFlags.rawValue)
        writer.append(fields)
    }

    func markIssue() {
        record("user.menuBarIssue", id: trace?.id, target: trace?.target)
    }

    func stop() {
        record("session.stopped")
        sampleTask?.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        writer.flush()
    }
}
