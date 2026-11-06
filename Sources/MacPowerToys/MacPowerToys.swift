import AppKit
import Combine
import SwiftUI

@main
struct MacPowerToys {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Mac Power Toys")
        item.button?.toolTip = "Mac Power Toys"
        statusItem = item
        ActivationDiagnostics.shared.statusItemVisible = { [weak self] in self?.statusItem?.isVisible ?? false }
        ActivationDiagnostics.shared.start()
        store.windowSwitcher.onMessage = { [weak self] message in
            self?.store.message = message
            self?.showSettings()
        }
        store.windowSwitcher.start()
        updateMenu()
        subscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateMenu() }
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func updateMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Mac Power Toys", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item("앱 단축키 설정…", action: #selector(showSettings), key: ","))
        let pause = item("단축키 일시 정지", action: #selector(togglePause))
        pause.state = store.isPaused ? .on : .off
        menu.addItem(pause)
        if !store.launchErrors.isEmpty {
            menu.addItem(item("앱 실행 오류 확인…", action: #selector(showSettings)))
        }
        menu.addItem(.separator())
        menu.addItem(item("메뉴 막대 문제 시점 기록", action: #selector(markIssue)))
        menu.addItem(item("진단 로그 폴더 열기…", action: #selector(openDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(item("Mac Power Toys 종료", action: #selector(quit), key: "q"))
        statusItem?.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
            )
            window.title = "Mac Power Toys — 앱 바로 전환"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("AppShortcutsSettings")
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.windowSwitcher.stop()
        ActivationDiagnostics.shared.stop()
    }

    @objc private func markIssue() { ActivationDiagnostics.shared.markIssue() }
    @objc private func openDiagnostics() { NSWorkspace.shared.open(ActivationDiagnostics.directory) }

    @objc private func togglePause() { store.isPaused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
