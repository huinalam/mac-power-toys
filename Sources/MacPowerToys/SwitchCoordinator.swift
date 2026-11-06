import AppKit

/// One submitted operation plus one replaceable pending request. Submitted
/// Launch Services operations cannot be cancelled; the latest request follows it.
@MainActor
final class SwitchCoordinator {
    struct Request {
        let id = UUID()
        let entry: AppEntry
        let source: String
        var isShortcut: Bool { source == "shortcut.modifiersReleased" }
    }

    static let heldModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    private(set) var pending: Request?
    private(set) var inFlight: UUID?
    private var releasedSince: TimeInterval?
    private var pollTask: Task<Void, Never>?
    private let automaticPolling: Bool
    private let modifiers: () -> NSEvent.ModifierFlags
    private let now: () -> TimeInterval
    private let isAllowed: (Request) -> Bool
    private let perform: (Request, @escaping @MainActor () -> Void) -> Void

    init(automaticPolling: Bool = true,
         modifiers: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isAllowed: @escaping (Request) -> Bool,
         perform: @escaping (Request, @escaping @MainActor () -> Void) -> Void) {
        self.automaticPolling = automaticPolling
        self.modifiers = modifiers
        self.now = now
        self.isAllowed = isAllowed
        self.perform = perform
    }

    func request(_ entry: AppEntry, source: String) {
        pending = Request(entry: entry, source: source)
        releasedSince = nil
        schedule()
    }

    func cancel(where predicate: (Request) -> Bool) {
        if let pending, predicate(pending) {
            self.pending = nil
            releasedSince = nil
        }
    }

    /// Also used by deterministic tests with an injected clock and key state.
    func tick() {
        guard let request = pending else { return }
        guard isAllowed(request) else {
            pending = nil
            releasedSince = nil
            return
        }
        guard inFlight == nil else { return }
        if request.isShortcut && !modifiers().intersection(Self.heldModifiers).isEmpty {
            releasedSince = nil
            return
        }
        // A short quiet period coalesces a burst and lets modifier release finish.
        guard let releasedSince else {
            self.releasedSince = now()
            return
        }
        guard now() - releasedSince >= 0.05 else { return }
        pending = nil
        self.releasedSince = nil
        inFlight = request.id
        perform(request) { [weak self] in
            guard let self, self.inFlight == request.id else { return }
            self.inFlight = nil
            self.releasedSince = nil
            self.schedule()
        }
    }

    private func schedule() {
        guard automaticPolling, pollTask == nil, pending != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                guard let self else { return }
                self.tick()
                if self.pending == nil || self.inFlight != nil {
                    self.pollTask = nil
                    return
                }
            }
        }
    }
}
