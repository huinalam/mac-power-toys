import AppKit
@preconcurrency import ApplicationServices
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class WindowSwitcherController: ObservableObject {
    static let forward = KeyboardShortcuts.Name("windowSwitcher.forward")
    static let backward = KeyboardShortcuts.Name("windowSwitcher.backward")
    static let shortcuts = [KeyboardShortcuts.Shortcut(.tab, modifiers: [.option]),
                            KeyboardShortcuts.Shortcut(.tab, modifiers: [.option, .shift])]

    @Published private(set) var enabled: Bool
    @Published private(set) var trusted = false
    @Published private(set) var windows: [SwitchableWindow] = []
    @Published private(set) var selection = WindowSelection()
    @Published private(set) var warning: String?
    var onMessage: ((String) -> Void)?
    var paused = false { didSet { if paused { cancel() } } }

    private let defaults: UserDefaults
    private let access = WindowAccess()
    private var panel: WindowSwitcherPanel?
    private var session: UUID?
    private var commitID: UUID?
    private var releaseTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObservers: [pid_t: AXObserver] = [:]
    private var recency: [String] = []
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "windowSwitcher.enabled")
    }

    func start() {
        guard !started else { return }
        started = true
        KeyboardShortcuts.onKeyDown(for: Self.forward) { [weak self] in self?.summon(direction: 1) }
        KeyboardShortcuts.onKeyDown(for: Self.backward) { [weak self] in self?.summon(direction: -1) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let name = note.name
                Task { @MainActor in
                    guard let self else { return }
                    if name == NSWorkspace.activeSpaceDidChangeNotification || name == NSWorkspace.sessionDidResignActiveNotification {
                        self.cancel()
                    }
                    if name == NSWorkspace.didTerminateApplicationNotification, let pid {
                        self.removeObserver(pid)
                    }
                    guard self.enabled, AXIsProcessTrusted() else { return }
                    self.observeApplications()
                    if name == NSWorkspace.didActivateApplicationNotification, let pid { self.trackFocus(pid) }
                }
            })
        }
        refreshPermission()
        configureShortcuts()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "windowSwitcher.enabled")
        if !value { cancel(); removeAllObservers() }
        refreshPermission()
        if started { configureShortcuts() }
    }

    func refreshPermission() {
        trusted = AXIsProcessTrusted()
        if enabled && trusted && started { observeApplications() }
        if !trusted { cancel(); removeAllObservers() }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermission()
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func configureShortcuts() {
        if enabled {
            KeyboardShortcuts.setShortcut(Self.shortcuts[0], for: Self.forward)
            KeyboardShortcuts.setShortcut(Self.shortcuts[1], for: Self.backward)
            KeyboardShortcuts.enable(Self.forward, Self.backward)
        } else {
            KeyboardShortcuts.disable(Self.forward, Self.backward)
        }
    }

    private func applications() -> [WindowApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.map { WindowApplication(pid: $0.processIdentifier, name: $0.localizedName ?? "앱", bundleIdentifier: $0.bundleIdentifier ?? "") }
    }

    func summon(direction: Int) {
        guard enabled, !paused else { return }
        refreshPermission()
        guard trusted else {
            onMessage?("창 전환기를 사용하려면 설정에서 손쉬운 사용 권한을 허용해주세요.")
            return
        }
        if session != nil { selection.move(direction); return }
        commitID = nil
        let token = UUID()
        session = token
        selection = WindowSelection()
        selection.move(direction)
        windows = []
        warning = nil
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var apps = applications()
        // Query the active app first when another app is slow.
        apps.sort { ($0.pid == frontPID ? 0 : 1) < ($1.pid == frontPID ? 0 : 1) }
        showPanel()
        releaseTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                guard let self, self.session == token else { return }
                if !NSEvent.modifierFlags.contains(.option) { self.releaseOption() }
                if !AXIsProcessTrusted() { self.cancel(); return }
            }
        }
        Task { [weak self, access] in
            let inventory = await access.inventory(applications: apps, frontPID: frontPID)
            guard let self, self.session == token else { return }
            if let focused = inventory.focusedID { self.remember(focused) }
            let ranks = Dictionary(uniqueKeysWithValues: self.recency.enumerated().map { ($0.element, $0.offset) })
            self.windows = inventory.windows.sorted {
                let a = ranks[$0.id] ?? Int.max, b = ranks[$1.id] ?? Int.max
                return a == b ? $0.stackingOrder < $1.stackingOrder : a < b
            }
            self.selection.loaded(self.windows.map(\.id), currentID: inventory.focusedID)
            self.warning = inventory.timedOut ? "응답이 느린 앱의 일부 창은 생략되었습니다." : nil
            if self.selection.commitWhenLoaded { self.confirm() }
        }
    }

    func move(_ direction: Int) { selection.move(direction) }

    func releaseOption() {
        guard session != nil else { return }
        selection.release()
        if !selection.isLoading { confirm() }
    }

    func confirm() {
        guard session != nil else { return }
        if selection.isLoading { selection.release(); return }
        let target = windows.first { $0.id == selection.selectedID }
        cancel()
        guard let target else { return }
        let token = UUID()
        commitID = token
        Task { [weak self, access] in
            guard await access.raise(target), let self, self.commitID == token else {
                if let self, self.commitID == token { self.onMessage?("선택한 창이 닫혔거나 접근할 수 없습니다.") }
                return
            }
            guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return }
            guard app.activate(options: []) else {
                self.onMessage?("선택한 창의 앱을 활성화하지 못했습니다."); return
            }
            // Raise the exact window again after submitting activation; never reopen
            // the application, which could create a different window.
            guard self.commitID == token else { return }
            let raised = await access.raise(target)
            guard self.commitID == token else { return }
            if raised { self.remember(target.id) }
            else { self.onMessage?("선택한 창을 앞으로 가져오지 못했습니다.") }
            self.commitID = nil
        }
    }

    func cancel() {
        session = nil
        commitID = nil
        releaseTask?.cancel()
        releaseTask = nil
        panel?.orderOut(nil)
    }

    private func showPanel() {
        if panel == nil {
            let panel = WindowSwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.backgroundColor = .windowBackgroundColor
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: WindowSwitcherView(controller: self))
            panel.onKey = { [weak self] code in
                switch code {
                case 53: self?.cancel()
                case 36: self?.confirm()
                case 123, 126: self?.move(-1)
                case 124, 125: self?.move(1)
                default: break
                }
            }
            panel.onOptionRelease = { [weak self] in self?.releaseOption() }
            panel.onResign = { [weak self] in self?.cancel() }
            self.panel = panel
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel?.setFrameOrigin(NSPoint(x: frame.midX - 290, y: frame.midY - 210))
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    private func remember(_ id: String) {
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
        recency = Array(recency.prefix(256))
    }

    private func trackFocus(_ pid: pid_t) {
        guard session == nil else { return }
        Task { [weak self, access] in
            let id = await access.focusedID(pid: pid)
            guard let self, self.session == nil, self.enabled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let id else { return }
            self.remember(id)
        }
    }

    private func observeApplications() {
        for app in applications() where axObservers[app.pid] == nil {
            var observer: AXObserver?
            let error = AXObserverCreate(app.pid, { _, element, _, context in
                guard let context else { return }
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                let controller = Unmanaged<WindowSwitcherController>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { controller.trackFocus(pid) }
            }, &observer)
            guard error == .success, let observer else { continue }
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.15)
            let result = AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque())
            guard result == .success else { continue }
            axObservers[app.pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func removeObserver(_ pid: pid_t) {
        if let observer = axObservers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func removeAllObservers() { for pid in Array(axObservers.keys) { removeObserver(pid) } }

    func stop() {
        cancel()
        removeAllObservers()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        KeyboardShortcuts.disable(Self.forward, Self.backward)
        KeyboardShortcuts.removeHandler(for: Self.forward)
        KeyboardShortcuts.removeHandler(for: Self.backward)
        started = false
    }
}

@MainActor
private final class WindowSwitcherPanel: NSPanel {
    var onKey: ((UInt16) -> Void)?
    var onOptionRelease: (() -> Void)?
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, [UInt16(53), 36, 123, 124, 125, 126].contains(event.keyCode) {
            onKey?(event.keyCode); return
        }
        if event.type == .flagsChanged && !event.modifierFlags.contains(.option) { onOptionRelease?(); return }
        super.sendEvent(event)
    }

    override func resignKey() { super.resignKey(); onResign?() }
}
