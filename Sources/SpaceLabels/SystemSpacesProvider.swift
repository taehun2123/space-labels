import AppKit
import ColorSync
import Darwin
import SpaceLabelsCore

enum SpacesReadError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: return "이 macOS에서 공간 조회 기능을 사용할 수 없습니다."
        case .invalidResponse: return "macOS가 예상하지 못한 공간 정보를 반환했습니다."
        }
    }
}

final class SystemSpacesProvider: @unchecked Sendable {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias ManagedSpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let library: UnsafeMutableRawPointer?
    private let connectionFunction: ConnectionFunction?
    private let managedSpacesFunction: ManagedSpacesFunction?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        library = handle
        if let handle,
           let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
           let spacesSymbol = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
            connectionFunction = unsafeBitCast(connectionSymbol, to: ConnectionFunction.self)
            managedSpacesFunction = unsafeBitCast(spacesSymbol, to: ManagedSpacesFunction.self)
        } else {
            connectionFunction = nil
            managedSpacesFunction = nil
        }
    }

    deinit {
        if let library { dlclose(library) }
    }

    func snapshot() throws -> SpaceSnapshot {
        guard let connectionFunction, let managedSpacesFunction else { throw SpacesReadError.unavailable }
        let connection = connectionFunction()
        guard let unmanaged = managedSpacesFunction(connection) else { throw SpacesReadError.unavailable }
        let raw = unmanaged.takeRetainedValue() as NSArray
        guard raw.count > 0 else { throw SpacesReadError.invalidResponse }
        let displays = try raw.map { item -> DisplaySnapshot in
            guard let dictionary = item as? NSDictionary,
                  let identifier = dictionary["Display Identifier"] as? String,
                  let rawSpaces = dictionary["Spaces"] as? [NSDictionary],
                  !rawSpaces.isEmpty else { throw SpacesReadError.invalidResponse }
            let spaces = try rawSpaces.map { value -> SystemSpace in
                guard let id = (value["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      let type = (value["type"] as? NSNumber)?.intValue else {
                    throw SpacesReadError.invalidResponse
                }
                let kind: SpaceKind = type == 0 ? .desktop : (type == 4 ? .application : .other(type))
                return SystemSpace(uuid: value["uuid"] as? String, runtimeID: id, kind: kind)
            }
            let current = dictionary["Current Space"] as? NSDictionary
            let currentID = (current?["ManagedSpaceID"] as? NSNumber)?.uint64Value
            return DisplaySnapshot(identifier: identifier, spaces: spaces, currentRuntimeID: currentID)
        }
        return SpaceSnapshot(displays: displays)
    }
}

enum ScreenResolver {
    static func screen(for identifier: String) -> NSScreen? {
        let screens = NSScreen.screens
        if identifier == "Main" {
            return screens.first { displayID(for: $0) == CGMainDisplayID() }
        }
        return screens.first { screen in
            guard let id = displayID(for: screen),
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { return false }
            let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
            return uuidString.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    static func screen(containingAXRect rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { appKitRect(fromAX: rect).intersects($0.frame) && $0.frame.contains(appKitPoint(fromAX: point)) }
    }

    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        let mainTop = screen(for: "Main")?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: mainTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitPoint(fromAX point: CGPoint) -> CGPoint {
        let mainTop = screen(for: "Main")?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: mainTop - point.y)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
