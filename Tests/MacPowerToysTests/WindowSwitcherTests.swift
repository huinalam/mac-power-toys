import AppKit
import KeyboardShortcuts
import Testing
@testable import MacPowerToys

struct WindowSelectionTests {
    @Test func forwardAndReverseWrapAcrossIndividualWindows() {
        var selection = WindowSelection()
        selection.move(1)
        selection.loaded(["chrome-1", "chrome-2", "finder"], currentID: "chrome-1")
        #expect(selection.selectedID == "chrome-2")
        selection.move(1)
        #expect(selection.selectedID == "finder")
        selection.move(1)
        #expect(selection.selectedID == "chrome-1")
        selection.move(-1)
        #expect(selection.selectedID == "finder")
    }

    @Test func quickReleaseAndRepeatedTabsSurviveAsyncLoading() {
        var selection = WindowSelection()
        selection.move(1)
        selection.move(1)
        selection.release()
        #expect(selection.isLoading)
        selection.loaded(["a", "b", "c"], currentID: "a")
        #expect(selection.commitWhenLoaded)
        #expect(selection.selectedID == "c")
    }

    @Test func anotherTabAfterQuickReleaseContinuesLoadingSession() {
        var selection = WindowSelection()
        selection.move(1)
        selection.release()
        selection.move(1)
        selection.loaded(["a", "b", "c"], currentID: "a")
        #expect(!selection.commitWhenLoaded)
        #expect(selection.selectedID == "c")
        selection.release()
        #expect(selection.commitWhenLoaded)
    }

    @Test func emptySingleAndUnknownCurrentWindowAreSafe() {
        var empty = WindowSelection()
        empty.move(-1)
        empty.loaded([], currentID: nil)
        empty.move(1)
        #expect(empty.selectedID == nil)
        var single = WindowSelection()
        single.move(1)
        single.loaded(["a"], currentID: "a")
        #expect(single.selectedID == "a")
        var unknown = WindowSelection()
        unknown.move(1)
        unknown.loaded(["a", "b"], currentID: nil)
        #expect(unknown.selectedID == "a")
        var reverse = WindowSelection()
        reverse.move(-1)
        reverse.loaded(["a", "b", "c"], currentID: "a")
        #expect(reverse.selectedID == "c")
    }

    @Test func windowBoundsMatchingAllowsRoundingButNotOtherWindows() {
        let rect = CGRect(x: 10, y: 20, width: 600, height: 400)
        #expect(WindowAccess.matches(rect, CGRect(x: 11, y: 21, width: 601, height: 400)))
        #expect(!WindowAccess.matches(rect, CGRect(x: 10, y: 500, width: 600, height: 400)))
    }
}

@Suite(.serialized)
@MainActor
struct WindowSwitcherIntegrationTests {
    @Test func optionalFeatureReservesItsShortcutsAndHonorsPause() {
        let defaults = UserDefaults(suiteName: "WindowSwitcherTests.\(UUID().uuidString)")!
        let store = AppStore(defaults: defaults)
        #expect(!store.windowSwitcher.enabled)
        store.setWindowSwitcherEnabled(true)
        let entry = AppEntry(name: "Test", bundleIdentifier: "test", path: "/missing.app")
        #expect(store.validate(WindowSwitcherController.shortcuts[0], for: entry) != .allow)
        #expect(store.validate(WindowSwitcherController.shortcuts[1], for: entry) != .allow)
        store.isPaused = true
        #expect(store.windowSwitcher.paused)
        store.setWindowSwitcherEnabled(false)
        #expect(store.validate(WindowSwitcherController.shortcuts[0], for: entry) == .allow)
        store.isPaused = false
    }

    @Test func existingAppShortcutIsNotOverwritten() throws {
        let defaults = UserDefaults(suiteName: "WindowSwitcherTests.\(UUID().uuidString)")!
        let entry = AppEntry(name: "Existing", bundleIdentifier: "test", path: "/missing.app")
        try SettingsRepository(defaults: defaults).save([entry])
        KeyboardShortcuts.setShortcut(WindowSwitcherController.shortcuts[0], for: entry.shortcutName)
        let store = AppStore(defaults: defaults)
        store.setWindowSwitcherEnabled(true)
        #expect(!store.windowSwitcher.enabled)
        #expect(store.message != nil)
        #expect(KeyboardShortcuts.getShortcut(for: entry.shortcutName) == WindowSwitcherController.shortcuts[0])
        store.remove(entry)
    }
}
