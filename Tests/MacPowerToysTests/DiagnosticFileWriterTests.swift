import Foundation
import Testing
@testable import MacPowerToys

struct DiagnosticFileWriterTests {
    private func records(_ directory: URL) throws -> [[String: String]] {
        let path = directory.appendingPathComponent("activation.jsonl")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try Data(contentsOf: path).split(separator: 0x0a).map {
            try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: String])
        }
    }

    @Test func recordsRemainValidJSONAndOrdered() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = DiagnosticFileWriter(directory: directory)
        writer.append(["event": "first", "value": "line\nbreak \"quoted\""])
        writer.append(["event": "second"])
        writer.flush()
        let result = try records(directory)
        #expect(result.count == 2)
        #expect(result[0]["value"] == "line\nbreak \"quoted\"")
        #expect(result[1]["event"] == "second")
    }

    @Test func sizeLimitDeletesOldestRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = DiagnosticFileWriter(directory: directory, maximumBytes: 200)
        for event in ["first", "second", "third"] { writer.append(["event": event]) }
        writer.flush()
        let result = try records(directory)
        #expect(result.last?["event"] == "third")
        #expect(!result.contains { $0["event"] == "first" })
        #expect(try Data(contentsOf: directory.appendingPathComponent("activation.jsonl")).count <= 200)
    }

    @Test func expiryWorksWithoutNewRecordsAndMigratesLegacyFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let old = ["event": "legacy", "timestamp": now.addingTimeInterval(-100).ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))]
        try (JSONSerialization.data(withJSONObject: old) + Data([10])).write(to: directory.appendingPathComponent("activation.previous.jsonl"))
        let writer = DiagnosticFileWriter(directory: directory, retention: 60)
        writer.append(["event": "recent"], now: now)
        writer.flush()
        #expect(try records(directory).map { $0["event"] } == ["recent"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("activation.previous.jsonl").path))
        writer.cleanup(now: now.addingTimeInterval(61))
        writer.flush()
        #expect(try records(directory).isEmpty)
    }
}
