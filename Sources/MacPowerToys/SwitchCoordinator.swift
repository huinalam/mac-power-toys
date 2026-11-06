import AppKit

/// One submitted operation plus one replaceable pending request. Submitted
/// Launch Services operations cannot be cancelled; the latest request follows it.
@MainActor
final class SwitchCoordinator {
    struct Request {
        let id = UUID()
        let entry: AppEntry
        let source: String
        var isShortcut: Bool { source == "shortcut.keyDown" }
    }

    private(set) var pending: Request?
    private(set) var inFlight: UUID?
    private let isAllowed: (Request) -> Bool
    private let perform: (Request, @escaping @MainActor () -> Void) -> Void

    init(isAllowed: @escaping (Request) -> Bool,
         perform: @escaping (Request, @escaping @MainActor () -> Void) -> Void) {
        self.isAllowed = isAllowed
        self.perform = perform
    }

    func request(_ entry: AppEntry, source: String) {
        pending = Request(entry: entry, source: source)
        drain()
    }

    func cancel(where predicate: (Request) -> Bool) {
        if let pending, predicate(pending) {
            self.pending = nil
        }
    }

    private func drain() {
        guard inFlight == nil, let request = pending else { return }
        pending = nil
        guard isAllowed(request) else { return }
        inFlight = request.id
        perform(request) { [weak self] in
            guard let self, self.inFlight == request.id else { return }
            self.inFlight = nil
            self.drain()
        }
    }
}
