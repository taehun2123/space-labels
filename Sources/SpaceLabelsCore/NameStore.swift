import Foundation
import Darwin

public final class NameStore {
    public let url: URL
    public private(set) var document: NameDocument

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                document = try Self.decode(url)
            } catch StoreError.unsupportedVersion {
                throw StoreError.unsupportedVersion
            } catch {
                let backup = url.appendingPathExtension("backup")
                let restored = try Self.decode(backup)
                let preserved = url.deletingLastPathComponent()
                    .appendingPathComponent("names.corrupt.\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: preserved)
                let staged = url.deletingLastPathComponent().appendingPathComponent(".names.restore.\(UUID().uuidString)")
                do {
                    try Data(contentsOf: backup).write(to: staged)
                    guard rename(staged.path, url.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: staged)
                    throw error
                }
                document = restored
            }
        } else {
            document = NameDocument()
        }
    }

    private static func decode(_ url: URL) throws -> NameDocument {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(NameDocument.self, from: data)
        guard decoded.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        return decoded
    }

    public func setName(_ raw: String, for spaceUUID: String, displayIdentifier: String) throws {
        let name = try NameRules.validated(raw)
        guard !spaceUUID.isEmpty else { throw StoreError.missingSpaceUUID }
        var updated = document
        if let index = updated.records.firstIndex(where: { $0.spaceUUID == spaceUUID }) {
            updated.records[index].name = name
            updated.records[index].lastDisplayIdentifier = displayIdentifier
        } else {
            updated.records.append(NameRecord(spaceUUID: spaceUUID, name: name, lastDisplayIdentifier: displayIdentifier))
        }
        try persist(updated)
    }

    public func clearName(for spaceUUID: String) throws {
        var updated = document
        updated.records.removeAll { $0.spaceUUID == spaceUUID }
        try persist(updated)
    }

    public func reassign(recordID: UUID, to spaceUUID: String, displayIdentifier: String) throws {
        guard !spaceUUID.isEmpty else { throw StoreError.missingSpaceUUID }
        var updated = document
        guard updated.records.contains(where: { $0.id == recordID }) else { throw StoreError.recordMissing }
        updated.records.removeAll { $0.spaceUUID == spaceUUID && $0.id != recordID }
        guard let target = updated.records.firstIndex(where: { $0.id == recordID }) else { throw StoreError.recordMissing }
        updated.records[target].spaceUUID = spaceUUID
        updated.records[target].lastDisplayIdentifier = displayIdentifier
        try persist(updated)
    }

    private func persist(_ updated: NameDocument) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        let staged = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: staged)
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("backup")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: url, to: backup)
                guard rename(staged.path, url.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } else {
                try FileManager.default.moveItem(at: staged, to: url)
            }
            document = updated
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }
}

public enum StoreError: LocalizedError {
    case unsupportedVersion
    case missingSpaceUUID
    case recordMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "저장 파일의 형식이 이 앱과 맞지 않습니다."
        case .missingSpaceUUID: return "이 공간의 식별자를 확인할 수 없습니다."
        case .recordMissing: return "이름 기록을 찾을 수 없습니다."
        }
    }
}
