import AppKit
import Combine
import KeyboardShortcuts
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    let windowSwitcher: WindowSwitcherController

    @Published private(set) var entries: [AppEntry] = []
    @Published var message: String?
    @Published private(set) var launchErrors: [UUID: String] = [:]
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: "shortcutsPaused")
            KeyboardShortcuts.isEnabled = !isPaused
            windowSwitcher.paused = isPaused
            if isPaused { switchCoordinator.cancel { $0.isShortcut } }
        }
    }

    private let defaults: UserDefaults
    private let repository: SettingsRepository
    private lazy var switchCoordinator = SwitchCoordinator(
        isAllowed: { [weak self] request in
            guard let self else { return false }
            if !request.isShortcut { return true }
            return !self.isPaused && self.entries.contains { $0.id == request.entry.id && $0.isEnabled }
        },
        perform: { [weak self] request, completion in
            guard let self else { completion(); return }
            self.performLaunch(request.entry, source: request.source, completion: completion)
        }
    )
    private var canSave = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        windowSwitcher = WindowSwitcherController(defaults: defaults)
        repository = SettingsRepository(defaults: defaults)
        isPaused = defaults.bool(forKey: "shortcutsPaused")
        do {
            entries = try repository.load()
        } catch {
            canSave = false
            message = "저장된 설정을 읽지 못했습니다. 기존 데이터를 보호하기 위해 변경을 저장하지 않습니다."
        }
        for entry in entries { register(entry) }
        KeyboardShortcuts.isEnabled = !isPaused
        windowSwitcher.paused = isPaused
        if windowSwitcher.enabled && entries.contains(where: {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: $0.shortcutName) else { return false }
            return WindowSwitcherController.shortcuts.contains(shortcut)
        }) {
            windowSwitcher.setEnabled(false)
            message = "기존 앱 단축키가 ⌥Tab 또는 ⇧⌥Tab을 사용 중이어서 창 전환기를 껐습니다."
        }
        refreshLoginStatus()
    }

    func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "단축키로 전환할 앱 선택"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                message = "\(url.lastPathComponent)은 유효한 앱이 아닙니다."
                continue
            }
            guard identifier != Bundle.main.bundleIdentifier else {
                message = "Mac Power Toys 자체는 등록할 수 없습니다."
                continue
            }
            if let index = entries.firstIndex(where: { $0.bundleIdentifier == identifier }) {
                entries[index].path = url.path
                launchErrors[entries[index].id] = nil
                continue
            }
            let entry = AppEntry(
                name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                bundleIdentifier: identifier,
                path: url.path
            )
            entries.append(entry)
            register(entry)
        }
        persist()
    }

    func remove(_ entry: AppEntry) {
        switchCoordinator.cancel { $0.entry.id == entry.id }
        KeyboardShortcuts.disable(entry.shortcutName)
        KeyboardShortcuts.removeHandler(for: entry.shortcutName)
        KeyboardShortcuts.reset(entry.shortcutName)
        entries.removeAll { $0.id == entry.id }
        launchErrors[entry.id] = nil
        persist()
    }

    func setEnabled(_ enabled: Bool, for entry: AppEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isEnabled = enabled
        if !enabled { switchCoordinator.cancel { $0.isShortcut && $0.entry.id == entry.id } }
        if enabled { KeyboardShortcuts.enable(entry.shortcutName) }
        else { KeyboardShortcuts.disable(entry.shortcutName) }
        persist()
    }

    func setWindowSwitcherEnabled(_ enabled: Bool) {
        if enabled, let conflict = entries.first(where: {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: $0.shortcutName) else { return false }
            return WindowSwitcherController.shortcuts.contains(shortcut)
        }) {
            message = "‘\(conflict.name)’의 단축키가 ⌥Tab 또는 ⇧⌥Tab과 겹칩니다. 먼저 해당 단축키를 변경해주세요."
            return
        }
        windowSwitcher.setEnabled(enabled)
    }

    func validate(_ shortcut: KeyboardShortcuts.Shortcut, for entry: AppEntry) -> KeyboardShortcuts.ValidationResult {
        if windowSwitcher.enabled && WindowSwitcherController.shortcuts.contains(shortcut) {
            return .disallow(reason: String("창 전환기가 사용하는 단축키입니다."))
        }
        if let conflict = entries.first(where: {
            $0.id != entry.id && KeyboardShortcuts.getShortcut(for: $0.shortcutName) == shortcut
        }) {
            return .disallow(reason: String("이미 ‘\(conflict.name)’에 지정된 단축키입니다."))
        }
        return .allow
    }

    func shortcutChanged(for entry: AppEntry) {
        // Recorder stores the shortcut. Reapply the per-app enabled state after recording.
        if !entry.isEnabled { KeyboardShortcuts.disable(entry.shortcutName) }
        objectWillChange.send()
    }

    func resolvedURL(for entry: AppEntry) -> URL? {
        let saved = URL(fileURLWithPath: entry.path)
        if Bundle(url: saved)?.bundleIdentifier == entry.bundleIdentifier { return saved }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier)
    }

    func launch(_ entry: AppEntry, source: String = "manual") {
        windowSwitcher.cancel()
        switchCoordinator.request(entry, source: source)
    }

    private func performLaunch(_ entry: AppEntry, source: String, completion: @escaping @MainActor () -> Void) {
        let diagnostics = ActivationDiagnostics.shared
        let request = diagnostics.begin(target: entry.bundleIdentifier, source: source)
        launchErrors[entry.id] = nil
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleIdentifier)
            .first(where: { !$0.isTerminated })
        if running?.isActive == true {
            diagnostics.record("switch.skipped.alreadyActive", id: request, target: entry.bundleIdentifier)
            completion()
            return
        }

        // Use Launch Services for both running and stopped apps. Avoid separately
        // unhiding and activating during a global hot-key event: those requests
        // can overlap the system's app/Space presentation transition.
        guard let url = running?.bundleURL ?? resolvedURL(for: entry) else {
            diagnostics.record("switch.failed.missingApp", id: request, target: entry.bundleIdentifier)
            launchErrors[entry.id] = "앱을 찾을 수 없습니다. ‘앱 추가’에서 다시 선택해주세요."
            completion()
            return
        }
        // NSWorkspace handles cooperative activation; no manual yield is needed.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.hides = false
        configuration.hidesOthers = false
        configuration.addsToRecentItems = false
        diagnostics.record("switch.openSubmitted", id: request, target: entry.bundleIdentifier)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            let errorDescription = error?.localizedDescription
            let errorDomain = (error as NSError?)?.domain ?? "none"
            let errorCode = (error as NSError?)?.code ?? 0
            let returnedPID = app?.processIdentifier ?? 0
            Task { @MainActor in
                defer { completion() }
                diagnostics.record("switch.openCompleted", id: request, target: entry.bundleIdentifier,
                                   extra: ["errorDomain": errorDomain, "errorCode": String(errorCode),
                                           "returnedPID": String(returnedPID)])
                guard let self else { return }
                guard self.entries.contains(where: { $0.id == entry.id }) else { return }
                self.launchErrors[entry.id] = errorDescription
            }
        }
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "로그인 시 실행 설정을 변경하지 못했습니다: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    private func register(_ entry: AppEntry) {
        KeyboardShortcuts.onKeyDown(for: entry.shortcutName) { [weak self] in
            guard let self, !self.isPaused,
                  let current = self.entries.first(where: { $0.id == entry.id }), current.isEnabled else { return }
            self.launch(current, source: "shortcut.keyDown")
        }
        if !entry.isEnabled { KeyboardShortcuts.disable(entry.shortcutName) }
    }

    private func persist() {
        guard canSave else { return }
        do { try repository.save(entries) }
        catch { message = "설정을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
}
