import XCTest
@testable import SpaceLabelsCore

final class SpaceLabelsCoreTests: XCTestCase {
    func testNameFollowsUUIDWhenDesktopsReorder() throws {
        let a = SystemSpace(uuid: "A", runtimeID: 10, kind: .desktop)
        let b = SystemSpace(uuid: "B", runtimeID: 20, kind: .desktop)
        let record = NameRecord(spaceUUID: "B", name: "회의", lastDisplayIdentifier: "Main")
        let before = Reconciliation(snapshot: SpaceSnapshot(displays: [DisplaySnapshot(identifier: "Main", spaces: [a, b], currentRuntimeID: 10)]), records: [record])
        let after = Reconciliation(snapshot: SpaceSnapshot(displays: [DisplaySnapshot(identifier: "Main", spaces: [b, a], currentRuntimeID: 10)]), records: [record])
        XCTAssertEqual(before.names["B"], "회의")
        XCTAssertEqual(after.names["B"], "회의")
        XCTAssertEqual(DesktopLabel.number(for: b, in: DisplaySnapshot(identifier: "Main", spaces: [b, a], currentRuntimeID: 10)), 1)
    }

    func testDeletedSpaceNameIsOrphanedRatherThanReused() {
        let replacement = SystemSpace(uuid: "NEW", runtimeID: 20, kind: .desktop)
        let record = NameRecord(spaceUUID: "OLD", name: "회의", lastDisplayIdentifier: "Main")
        let result = Reconciliation(snapshot: SpaceSnapshot(displays: [DisplaySnapshot(identifier: "Main", spaces: [replacement], currentRuntimeID: 20)]), records: [record])
        XCTAssertTrue(result.names.isEmpty)
        XCTAssertEqual(result.orphaned, [record])
    }

    func testFullscreenAndSplitViewNamesFollowTheirUUIDs() {
        let desktop = SystemSpace(uuid: "D", runtimeID: 1, kind: .desktop)
        let fullscreen = SystemSpace(uuid: "F", runtimeID: 2, kind: .application)
        let splitView = SystemSpace(uuid: "S", runtimeID: 3, kind: .application)
        let records = [
            NameRecord(spaceUUID: "F", name: "자료 조사", lastDisplayIdentifier: "Main"),
            NameRecord(spaceUUID: "S", name: "문서 비교", lastDisplayIdentifier: "Main")
        ]
        let snapshot = SpaceSnapshot(displays: [
            DisplaySnapshot(identifier: "Main", spaces: [splitView, desktop, fullscreen], currentRuntimeID: 3)
        ])
        let result = Reconciliation(snapshot: snapshot, records: records)
        XCTAssertEqual(result.names["F"], "자료 조사")
        XCTAssertEqual(result.names["S"], "문서 비교")
        XCTAssertTrue(result.orphaned.isEmpty)
        XCTAssertEqual(DesktopLabel.number(for: desktop, in: snapshot.displays[0]), 1)
    }

    func testDuplicateSystemUUIDDoesNotAssignName() {
        let duplicate = SystemSpace(uuid: "A", runtimeID: 10, kind: .desktop)
        let record = NameRecord(spaceUUID: "A", name: "개발", lastDisplayIdentifier: "Main")
        let conflicting = SystemSpace(uuid: "A", runtimeID: 11, kind: .desktop)
        let snapshot = SpaceSnapshot(displays: [DisplaySnapshot(identifier: "Main", spaces: [duplicate, conflicting], currentRuntimeID: 10)])
        let result = Reconciliation(snapshot: snapshot, records: [record])
        XCTAssertTrue(result.names.isEmpty)
        XCTAssertEqual(result.orphaned, [record])
        XCTAssertTrue(result.ambiguousUUIDs.contains("A"))
    }

    func testSharedSpaceOnTwoDisplaysKeepsOneName() {
        let shared = SystemSpace(uuid: "A", runtimeID: 10, kind: .desktop)
        let record = NameRecord(spaceUUID: "A", name: "개발", lastDisplayIdentifier: "Main")
        let snapshot = SpaceSnapshot(displays: [
            DisplaySnapshot(identifier: "Main", spaces: [shared], currentRuntimeID: 10),
            DisplaySnapshot(identifier: "Secondary", spaces: [shared], currentRuntimeID: 10)
        ])
        let result = Reconciliation(snapshot: snapshot, records: [record])
        XCTAssertEqual(result.names["A"], "개발")
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testSaveFailureKeepsLastDocumentAndUnicodeName() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".test-data").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("names.json")
        let store = try NameStore(url: file)
        try store.setName("  개발 👩🏽‍💻  ", for: "A", displayIdentifier: "Main")
        XCTAssertEqual(store.document.records.first?.name, "개발 👩🏽‍💻")
        let reopened = try NameStore(url: file)
        XCTAssertEqual(reopened.document.records.first?.name, "개발 👩🏽‍💻")
        XCTAssertThrowsError(try store.setName("\n\n", for: "A", displayIdentifier: "Main"))
        XCTAssertEqual(store.document.records.first?.name, "개발 👩🏽‍💻")
    }

    func testCorruptCurrentFileRestoresLastBackupAndPreservesCorruptFile() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".test-data").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("names.json")
        let store = try NameStore(url: file)
        try store.setName("개발", for: "A", displayIdentifier: "Main")
        try store.setName("회의", for: "B", displayIdentifier: "Main")
        try Data("{broken".utf8).write(to: file)

        let restored = try NameStore(url: file)
        XCTAssertEqual(restored.document.records.map(\.name), ["개발"])
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("names.corrupt.") })
    }

    func testWindowNamePersistsForItsAppAndOriginalTitle() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".test-data").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("window-names.json")
        let key = "com.example.editor\u{1F}Report.pdf"
        let store = try WindowNameStore(url: file)
        try store.setName("  이번 주 보고서  ", for: key)
        XCTAssertEqual(store.document.names[key], "이번 주 보고서")
        XCTAssertEqual(try WindowNameStore(url: file).document.names[key], "이번 주 보고서")
        try store.clearName(for: key)
        XCTAssertNil(store.document.names[key])
    }
}
