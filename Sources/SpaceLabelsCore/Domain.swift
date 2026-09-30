import Foundation

public enum SpaceKind: Equatable {
    case desktop
    case application
    case other(Int)
}

public struct SystemSpace: Equatable {
    public let uuid: String?
    public let runtimeID: UInt64
    public let kind: SpaceKind

    public init(uuid: String?, runtimeID: UInt64, kind: SpaceKind) {
        self.uuid = uuid?.isEmpty == false ? uuid : nil
        self.runtimeID = runtimeID
        self.kind = kind
    }
}

public struct DisplaySnapshot: Equatable {
    public let identifier: String
    public let spaces: [SystemSpace]
    public let currentRuntimeID: UInt64?

    public init(identifier: String, spaces: [SystemSpace], currentRuntimeID: UInt64?) {
        self.identifier = identifier
        self.spaces = spaces
        self.currentRuntimeID = currentRuntimeID
    }

    public var desktops: [SystemSpace] { spaces.filter { $0.kind == .desktop } }
}

public struct SpaceSnapshot: Equatable {
    public let displays: [DisplaySnapshot]

    public init(displays: [DisplaySnapshot]) {
        self.displays = displays
    }
}

public enum NameError: LocalizedError, Equatable {
    case empty
    case tooLong
    case invalidCharacter

    public var errorDescription: String? {
        switch self {
        case .empty: return "이름을 입력하십시오."
        case .tooLong: return "이름은 40자 이하로 입력하십시오."
        case .invalidCharacter: return "줄바꿈과 제어 문자는 이름에 사용할 수 없습니다."
        }
    }
}

public enum NameRules {
    public static func validated(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NameError.empty }
        guard name.count <= 40 else { throw NameError.tooLong }
        guard name.unicodeScalars.allSatisfy({ scalar in
            let value = scalar.value
            return value >= 0x20 && !(0x7F...0x9F).contains(value) && !CharacterSet.newlines.contains(scalar)
        }) else {
            throw NameError.invalidCharacter
        }
        return name.precomposedStringWithCanonicalMapping
    }
}

public struct NameRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public var spaceUUID: String
    public var name: String
    public var lastDisplayIdentifier: String

    public init(id: UUID = UUID(), spaceUUID: String, name: String, lastDisplayIdentifier: String) {
        self.id = id
        self.spaceUUID = spaceUUID
        self.name = name
        self.lastDisplayIdentifier = lastDisplayIdentifier
    }
}

public struct NameDocument: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var records: [NameRecord] = []

    public init(records: [NameRecord] = []) {
        self.records = records
    }
}

public struct NameBinding: Equatable {
    public let spaceUUID: String
    public let name: String
}

public struct Reconciliation: Equatable {
    public let names: [String: String]
    public let orphaned: [NameRecord]
    public let ambiguousUUIDs: Set<String>

    public init(snapshot: SpaceSnapshot, records: [NameRecord]) {
        let identities = snapshot.displays.flatMap(\.spaces).compactMap { space -> (String, UInt64)? in
            guard let uuid = space.uuid else { return nil }
            return (uuid, space.runtimeID)
        }
        let systemIDs = Dictionary(identities.map { ($0.0, Set([$0.1])) }, uniquingKeysWith: { $0.union($1) })
        let recordCounts = Dictionary(records.map { ($0.spaceUUID, 1) }, uniquingKeysWith: +)
        let ambiguous = Set(systemIDs.filter { $0.value.count != 1 }.keys)
            .union(recordCounts.filter { $0.value != 1 }.keys)
        var resolved: [String: String] = [:]
        var unresolved: [NameRecord] = []
        for record in records {
            if systemIDs[record.spaceUUID]?.count == 1 && recordCounts[record.spaceUUID] == 1 && !ambiguous.contains(record.spaceUUID) {
                resolved[record.spaceUUID] = record.name
            } else {
                unresolved.append(record)
            }
        }
        names = resolved
        orphaned = unresolved
        ambiguousUUIDs = ambiguous
    }
}

public enum DesktopLabel {
    public static func number(for space: SystemSpace, in display: DisplaySnapshot) -> Int? {
        guard space.kind == .desktop else { return nil }
        return display.desktops.firstIndex(of: space).map { $0 + 1 }
    }
}
