import AppKit
import ApplicationServices

struct AXSpaceItem {
    let title: String
    let frame: CGRect
}

struct AXWindowItem {
    let title: String
    let identifier: String?
    let frame: CGRect
    let windowID: CGWindowID?
}

struct MissionControlScan {
    let spaces: [AXSpaceItem]
    let windows: [AXWindowItem]
}

final class DockAXScanner: @unchecked Sendable {
    func scan() -> MissionControlScan? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        let rootChildren = children(of: root)
        guard let missionControl = rootChildren.first(where: { identifier(of: $0) == "mc" })
                ?? descendants(of: root, limit: 200).first(where: { identifier(of: $0) == "mc" }) else {
            return nil
        }
        let displays = children(of: missionControl).filter { identifier(of: $0) == "mc.display" }
        guard !displays.isEmpty else { return nil }
        var spaces: [AXSpaceItem] = []
        var windows: [AXWindowItem] = []
        for display in displays {
            let groups = children(of: display)
            if let spacesGroup = groups.first(where: { identifier(of: $0) == "mc.spaces" }),
               let list = children(of: spacesGroup).first(where: { identifier(of: $0) == "mc.spaces.list" }) {
                for element in children(of: list) {
                    guard let title = title(of: element), let frame = frame(of: element),
                          frame.width >= 30, frame.height >= 20 else { continue }
                    spaces.append(AXSpaceItem(title: title, frame: frame))
                }
            }
            if let group = groups.first(where: { identifier(of: $0) == "mc.windows" }) {
                for element in children(of: group) {
                    guard let title = title(of: element), let frame = frame(of: element),
                          frame.width >= 70, frame.height >= 50 else { continue }
                    windows.append(AXWindowItem(title: title, identifier: identifier(of: element),
                                                frame: frame, windowID: AXWindowID.of(element)))
                }
            }
        }
        return MissionControlScan(spaces: spaces, windows: windows)
    }

    private func descendants(of root: AXUIElement, limit: Int) -> [AXUIElement] {
        var queue = children(of: root)
        var result: [AXUIElement] = []
        var offset = 0
        while offset < queue.count && offset < limit {
            let element = queue[offset]
            offset += 1
            result.append(element)
            queue.append(contentsOf: children(of: element))
        }
        return result
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, attribute: kAXChildrenAttribute as CFString) ?? []
    }

    private func identifier(of element: AXUIElement) -> String? {
        value(of: element, attribute: "AXIdentifier" as CFString)
    }

    private func title(of element: AXUIElement) -> String? {
        for key in [kAXTitleAttribute as CFString, kAXDescriptionAttribute as CFString] {
            if let text: String = value(of: element, attribute: key) {
                let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !result.isEmpty { return result }
            }
        }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let wrapped: AXValue = value(of: element, attribute: "AXFrame" as CFString) else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(wrapped, .cgRect, &rect) ? rect : nil
    }

    private func value<T>(of element: AXUIElement, attribute: CFString) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
        return result as? T
    }

    static func desktopNumber(from raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Desktop", "데스크톱", "데스크탑"] where text.hasPrefix(prefix) {
            let suffix = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let value = Int(suffix), value > 0 { return value }
        }
        return nil
    }
}
