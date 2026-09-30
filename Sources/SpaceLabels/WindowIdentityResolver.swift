import AppKit
import ApplicationServices
import Darwin

enum AXWindowID {
    private typealias Function = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let function: Function? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    static func of(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return function?(element, &id) == .success && id != 0 ? id : nil
    }
}

struct ResolvedWindow {
    let title: String
    let frame: CGRect
    let key: String
    let persistent: Bool
}

final class WindowIdentityResolver: @unchecked Sendable {
    private struct LiveWindow {
        let id: CGWindowID?
        let title: String
        let bundle: String
    }

    private var catalogAt = Date.distantPast
    private var catalog: [LiveWindow] = []

    func resolve(_ items: [AXWindowItem]) -> [ResolvedWindow] {
        if Date().timeIntervalSince(catalogAt) > 1 {
            catalog = makeCatalog()
            catalogAt = Date()
        }
        let thumbnailCounts = Dictionary(items.map { ($0.title, 1) }, uniquingKeysWith: +)
        var sessionOrdinals: [String: Int] = [:]
        return items.map { item in
            sessionOrdinals[item.title, default: 0] += 1
            let idMatch = item.windowID.flatMap { id in catalog.first(where: { $0.id == id }) }
            let titleMatches = catalog.filter { $0.title == item.title }
            let match = idMatch ?? (titleMatches.count == 1 ? titleMatches[0] : nil)
            let persistent = thumbnailCounts[item.title] == 1 && titleMatches.count == 1 && match?.title == item.title
            let key = persistent
                ? "\(match!.bundle)\u{1F}\(item.title)"
                : idMatch.map { "session:id:\($0.id!)" }
                    ?? "session:unresolved:\(item.identifier ?? ""):\(item.title):\(sessionOrdinals[item.title]!)"
            return ResolvedWindow(title: item.title, frame: item.frame, key: key, persistent: persistent)
        }
    }

    private func makeCatalog() -> [LiveWindow] {
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = raw.compactMap { info -> (id: CGWindowID, pid: pid_t, title: String?)? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            return (number.uint32Value, pidNumber.int32Value, info[kCGWindowName as String] as? String)
        }
        var accessibleByID: [CGWindowID: LiveWindow] = [:]
        var accessibleWithoutID: [LiveWindow] = []
        var pidsWithAX = Set<pid_t>()
        for pid in Set(visible.map(\.pid)) {
            guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &result) == .success,
                  let windows = result as? [AXUIElement] else { continue }
            if !windows.isEmpty { pidsWithAX.insert(pid) }
            for window in windows {
                var titleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                      let title = titleValue as? String, !title.isEmpty else { continue }
                let record = LiveWindow(id: AXWindowID.of(window), title: title, bundle: bundle)
                if let id = record.id { accessibleByID[id] = record }
                else { accessibleWithoutID.append(record) }
            }
        }
        var seen = Set<CGWindowID>()
        var records: [LiveWindow] = []
        for window in visible {
            guard let bundle = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier else { continue }
            seen.insert(window.id)
            if let accessible = accessibleByID[window.id] {
                records.append(accessible)
            } else if !pidsWithAX.contains(window.pid), let title = window.title, !title.isEmpty {
                records.append(LiveWindow(id: window.id, title: title, bundle: bundle))
            }
        }
        records.append(contentsOf: accessibleByID.filter { !seen.contains($0.key) }.map(\.value))
        records.append(contentsOf: accessibleWithoutID)
        return records
    }
}

enum WindowOverlayMatcher {
    static func placements(windows: [ResolvedWindow], persistentNames: [String: String], sessionNames: [String: String]) -> [LabelPlacement] {
        windows.compactMap { window in
            let hit = ScreenResolver.appKitRect(fromAX: window.frame)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: hit.midX, y: hit.midY)) }),
                  hit.width >= 70, hit.height >= 50 else { return nil }
            let badge = CGRect(x: hit.minX + 8, y: hit.maxY - 30, width: min(hit.width - 16, 240), height: 23)
            return LabelPlacement(screen: screen, frame: badge, hitFrame: hit,
                                  name: window.persistent ? persistentNames[window.key] : sessionNames[window.key],
                                  title: window.title,
                                  target: .window(key: window.key, persistent: window.persistent))
        }
    }
}
