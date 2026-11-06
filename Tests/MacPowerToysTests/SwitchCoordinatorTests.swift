import Testing
@testable import MacPowerToys

@MainActor
struct SwitchCoordinatorTests {
    private func entry(_ name: String) -> AppEntry {
        AppEntry(name: name, bundleIdentifier: "test.\(name)", path: "/missing/\(name).app")
    }

    @Test func startsImmediatelyWithoutWaitingForTimerOrKeyRelease() {
        var targets: [String] = []
        let queue = SwitchCoordinator(isAllowed: { _ in true }, perform: { request, done in
            targets.append(request.entry.name)
            done()
        })
        queue.request(entry("A"), source: "shortcut.keyDown")
        #expect(targets == ["A"])
        #expect(queue.inFlight == nil)
        queue.request(entry("B"), source: "shortcut.keyDown")
        #expect(targets == ["A", "B"])
    }

    @Test func serializesSubmittedOperationsAndKeepsOnlyLatestPending() {
        var targets: [String] = []
        var completions: [@MainActor () -> Void] = []
        let queue = SwitchCoordinator(isAllowed: { _ in true }, perform: { request, done in
            targets.append(request.entry.name); completions.append(done)
        })
        queue.request(entry("A"), source: "manual")
        queue.request(entry("B"), source: "manual")
        queue.request(entry("C"), source: "shortcut.keyDown")
        #expect(targets == ["A"])
        completions[0]()
        #expect(targets == ["A", "C"])
        let activeID = queue.inFlight
        completions[0]()
        #expect(queue.inFlight == activeID)
        completions[1]()
        #expect(queue.inFlight == nil)
    }

    @Test func cancellationAndEligibilityPreventStaleLaunches() {
        var allowed = true
        var targets: [String] = []
        var completions: [@MainActor () -> Void] = []
        let queue = SwitchCoordinator(isAllowed: { _ in allowed }, perform: { request, done in
            targets.append(request.entry.name); completions.append(done)
        })
        queue.request(entry("A"), source: "manual")
        queue.request(entry("B"), source: "shortcut.keyDown")
        queue.cancel { $0.isShortcut }
        completions[0]()
        #expect(targets == ["A"])
        queue.request(entry("C"), source: "manual")
        queue.request(entry("D"), source: "shortcut.keyDown")
        allowed = false
        completions[1]()
        #expect(targets == ["A", "C"])
        #expect(queue.pending == nil)
        allowed = true
        queue.request(entry("E"), source: "manual")
        queue.request(entry("F"), source: "manual")
        queue.cancel { $0.isShortcut }
        completions[2]()
        #expect(targets == ["A", "C", "E", "F"])
    }
}
