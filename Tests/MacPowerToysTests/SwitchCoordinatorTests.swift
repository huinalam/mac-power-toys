import AppKit
import Testing
@testable import MacPowerToys

@MainActor
struct SwitchCoordinatorTests {
    private func entry(_ name: String) -> AppEntry {
        AppEntry(name: name, bundleIdentifier: "test.\(name)", path: "/missing/\(name).app")
    }

    @Test func waitsForAllModifiersAndRestartsQuietPeriod() {
        var flags: NSEvent.ModifierFlags = [.option, .command]
        var time = 0.0
        var launches = 0
        let queue = SwitchCoordinator(automaticPolling: false, modifiers: { flags }, now: { time },
            isAllowed: { _ in true }, perform: { _, done in launches += 1; done() })
        queue.request(entry("A"), source: "shortcut.modifiersReleased")
        queue.tick()
        flags = [.option]; time = 1; queue.tick()
        #expect(launches == 0)
        flags = []; queue.tick(); time = 1.02; queue.tick()
        #expect(launches == 0)
        flags = [.shift]; queue.tick()
        flags = []; time = 2; queue.tick(); time = 2.06; queue.tick()
        #expect(launches == 1)
        queue.tick()
        #expect(launches == 1)
    }

    @Test func newestTargetWinsAndCapsLockDoesNotBlock() {
        var time = 0.0
        var targets: [String] = []
        let queue = SwitchCoordinator(automaticPolling: false, modifiers: { [.capsLock] }, now: { time },
            isAllowed: { _ in true }, perform: { request, done in targets.append(request.entry.name); done() })
        queue.request(entry("A"), source: "shortcut.modifiersReleased")
        queue.tick()
        queue.request(entry("B"), source: "shortcut.modifiersReleased")
        queue.request(entry("C"), source: "shortcut.modifiersReleased")
        queue.tick(); time = 0.06; queue.tick()
        #expect(targets == ["C"])
    }

    @Test func serializesSubmittedOperationsAndKeepsOnlyLatestPending() {
        var time = 0.0
        var targets: [String] = []
        var completions: [@MainActor () -> Void] = []
        let queue = SwitchCoordinator(automaticPolling: false, modifiers: { [] }, now: { time },
            isAllowed: { _ in true }, perform: { request, done in targets.append(request.entry.name); completions.append(done) })
        queue.request(entry("A"), source: "manual")
        queue.tick(); time = 0.1; queue.tick()
        queue.request(entry("B"), source: "manual")
        queue.request(entry("C"), source: "shortcut.modifiersReleased")
        time = 1; queue.tick()
        #expect(targets == ["A"])
        completions[0]()
        queue.tick(); time = 1.1; queue.tick()
        #expect(targets == ["A", "C"])
        let activeID = queue.inFlight
        completions[0]() // Stale/double completions cannot finish the newer request.
        #expect(queue.inFlight == activeID)
        completions[1]()
        #expect(queue.inFlight == nil)
    }

    @Test func cancellationAndEligibilityPreventStaleLaunches() {
        var time = 0.0
        var allowed = true
        var launches = 0
        let app = entry("A")
        let queue = SwitchCoordinator(automaticPolling: false, modifiers: { [] }, now: { time },
            isAllowed: { _ in allowed }, perform: { _, done in launches += 1; done() })
        queue.request(app, source: "shortcut.modifiersReleased")
        queue.tick()
        queue.cancel { $0.isShortcut }
        time = 1; queue.tick()
        queue.request(app, source: "shortcut.modifiersReleased")
        queue.tick(); allowed = false; time = 2; queue.tick()
        #expect(launches == 0)
        #expect(queue.pending == nil)
        allowed = true
        queue.request(app, source: "manual")
        queue.cancel { $0.isShortcut } // Pausing shortcuts does not cancel a manual launch.
        queue.tick(); time = 2.1; queue.tick()
        #expect(launches == 1)
    }
}
