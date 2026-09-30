import Foundation
import Darwin

public struct WindowNameDocument: Codable {
    public var schemaVersion = 1
    public var names: [String: String] = [:]

    public init() {}
}

public final class WindowNameStore {
    public let url: URL
    public private(set) var document: WindowNameDocument

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                document = try Self.decode(url)
            } catch {
                let backup = url.appendingPathExtension("backup")
                let recovered = try Self.decode(backup)
                let preserved = url.deletingLastPathComponent()
                    .appendingPathComponent("window-names.corrupt.\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: preserved)
                try Data(contentsOf: backup).write(to: url, options: .atomic)
                document = recovered
            }
        } else {
            document = WindowNameDocument()
        }
    }

    public func setName(_ raw: String, for key: String) throws {
        guard !key.isEmpty else { throw StoreError.recordMissing }
        var updated = document
        updated.names[key] = try NameRules.validated(raw)
        try persist(updated)
    }

    public func clearName(for key: String) throws {
        var updated = document
        updated.names.removeValue(forKey: key)
        try persist(updated)
    }

    private static func decode(_ url: URL) throws -> WindowNameDocument {
        let decoded = try JSONDecoder().decode(WindowNameDocument.self, from: Data(contentsOf: url))
        guard decoded.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        return decoded
    }

    private func persist(_ updated: WindowNameDocument) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        let temporary = directory.appendingPathComponent(".window-names.\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("backup")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: url, to: backup)
            }
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            document = updated
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
