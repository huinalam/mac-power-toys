import Foundation
import KeyboardShortcuts

struct AppEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var path: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, bundleIdentifier: String, path: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.isEnabled = isEnabled
    }

    @MainActor var shortcutName: KeyboardShortcuts.Name {
        .init("app.\(id.uuidString)")
    }
}

struct SettingsRepository {
    let defaults: UserDefaults
    static let entriesKey = "applicationEntries.v1"

    func load() throws -> [AppEntry] {
        guard let data = defaults.data(forKey: Self.entriesKey) else { return [] }
        return try JSONDecoder().decode([AppEntry].self, from: data)
    }

    func save(_ entries: [AppEntry]) throws {
        defaults.set(try JSONEncoder().encode(entries), forKey: Self.entriesKey)
    }
}
