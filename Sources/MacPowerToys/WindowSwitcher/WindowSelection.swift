import Foundation

/// Pure selection state; asynchronous enumeration may finish after Option is released.
struct WindowSelection {
    private(set) var ids: [String] = []
    private(set) var selectedIndex: Int?
    private(set) var isLoading = true
    private(set) var commitWhenLoaded = false
    private var steps = 0

    var selectedID: String? { selectedIndex.map { ids[$0] } }

    mutating func move(_ delta: Int) {
        if isLoading { commitWhenLoaded = false; steps += delta; return }
        guard !ids.isEmpty else { return }
        selectedIndex = Self.wrap((selectedIndex ?? 0) + delta, count: ids.count)
    }

    mutating func loaded(_ ids: [String], currentID: String?) {
        self.ids = ids
        isLoading = false
        guard !ids.isEmpty else { selectedIndex = nil; return }
        // With an identified current window, the first Tab selects its successor.
        // Without one, the first forward Tab selects the first available window.
        let base = currentID.flatMap { ids.firstIndex(of: $0) } ?? (steps >= 0 ? -1 : 0)
        selectedIndex = Self.wrap(base + steps, count: ids.count)
    }

    mutating func release() { commitWhenLoaded = true }

    private static func wrap(_ index: Int, count: Int) -> Int { (index % count + count) % count }
}
