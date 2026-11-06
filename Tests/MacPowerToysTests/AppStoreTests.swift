import Foundation
import KeyboardShortcuts
import Testing
@testable import MacPowerToys

@Suite(.serialized)
@MainActor
struct AppStoreTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MacPowerToysTests.\(UUID().uuidString)")!
    }

    @Test func settingsSurviveRelaunch() throws {
        let defaults = isolatedDefaults()
        let repository = SettingsRepository(defaults: defaults)
        let entry = AppEntry(name: "Safari", bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app", isEnabled: false)
        try repository.save([entry])
        #expect(try repository.load() == [entry])
        let store = AppStore(defaults: defaults)
        #expect(store.entries == [entry])
        #expect(!KeyboardShortcuts.isEnabled(for: entry.shortcutName))
        store.setEnabled(true, for: entry)
        #expect(try repository.load().first?.isEnabled == true)
        store.remove(entry)
    }

    @Test func duplicateShortcutIsRejectedEvenWhenOtherEntryDisabled() throws {
        let defaults = isolatedDefaults()
        let first = AppEntry(name: "First", bundleIdentifier: "test.first", path: "/missing/first.app", isEnabled: false)
        let second = AppEntry(name: "Second", bundleIdentifier: "test.second", path: "/missing/second.app")
        try SettingsRepository(defaults: defaults).save([first, second])
        let store = AppStore(defaults: defaults)
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option, .control])
        KeyboardShortcuts.setShortcut(shortcut, for: first.shortcutName)
        #expect(store.validate(shortcut, for: first) == .allow)
        #expect(store.validate(shortcut, for: second) != .allow)
        store.remove(first)
        #expect(KeyboardShortcuts.getShortcut(for: first.shortcutName) == nil)
        #expect(store.validate(shortcut, for: second) == .allow)
        store.remove(second)
    }

    @Test func pausePersistsAndMissingAppReportsFailure() {
        let defaults = isolatedDefaults()
        let store = AppStore(defaults: defaults)
        store.isPaused = true
        #expect(defaults.bool(forKey: "shortcutsPaused"))
        #expect(!KeyboardShortcuts.isEnabled)
        let missing = AppEntry(name: "Missing", bundleIdentifier: "dev.macpowertoys.nonexistent", path: "/missing.app")
        store.launch(missing)
        #expect(store.launchErrors[missing.id] != nil)
        store.isPaused = false
    }

    @Test func corruptSettingsArePreserved() {
        let defaults = isolatedDefaults()
        let invalid = Data("invalid".utf8)
        defaults.set(invalid, forKey: SettingsRepository.entriesKey)
        let store = AppStore(defaults: defaults)
        #expect(store.message != nil)
        #expect(store.entries.isEmpty)
        store.remove(AppEntry(name: "Unused", bundleIdentifier: "unused", path: "/unused"))
        #expect(defaults.data(forKey: SettingsRepository.entriesKey) == invalid)
    }
}
