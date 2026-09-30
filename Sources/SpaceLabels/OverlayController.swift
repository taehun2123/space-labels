import AppKit
import SpaceLabelsCore

enum OverlayTarget {
    case space(uuid: String, displayIdentifier: String)
    case window(key: String, persistent: Bool)
}

struct LabelPlacement {
    let screen: NSScreen
    let frame: CGRect
    let hitFrame: CGRect
    let name: String?
    let title: String
    let target: OverlayTarget
}

enum OverlayMatcher {
    static func placements(snapshot: SpaceSnapshot, names: [String: String], items: [AXSpaceItem], ambiguousUUIDs: Set<String>) -> [LabelPlacement] {
        var result: [LabelPlacement] = []
        for display in snapshot.displays {
            guard let screen = ScreenResolver.screen(for: display.identifier) else { continue }
            let visible = items.filter { item in
                let frame = ScreenResolver.appKitRect(fromAX: item.frame)
                return screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
            }.sorted { $0.frame.midX < $1.frame.midX }
            guard visible.count == display.spaces.count else { continue }
            var desktopIndex = 0
            var anchorsMatch = true
            for (index, space) in display.spaces.enumerated() where space.kind == .desktop {
                desktopIndex += 1
                if DockAXScanner.desktopNumber(from: visible[index].title) != desktopIndex {
                    anchorsMatch = false
                    break
                }
            }
            guard anchorsMatch else { continue }
            for (index, space) in display.spaces.enumerated() {
                guard let uuid = space.uuid, !ambiguousUUIDs.contains(uuid) else { continue }
                let item = visible[index]
                let source = item.frame
                let labelRect = CGRect(x: source.minX, y: max(0, source.minY - 32),
                                       width: source.width, height: 26)
                let frame = ScreenResolver.appKitRect(fromAX: labelRect)
                let padded = CGRect(x: frame.minX - 7, y: frame.minY - 3,
                                    width: frame.width + 14, height: max(frame.height + 6, 22))
                guard screen.frame.contains(CGPoint(x: padded.midX, y: padded.midY)) else { continue }
                let hit = ScreenResolver.appKitRect(fromAX: item.frame).union(padded)
                guard screen.frame.contains(CGPoint(x: hit.midX, y: hit.midY)) else { continue }
                result.append(LabelPlacement(screen: screen, frame: padded, hitFrame: hit,
                                             name: names[uuid], title: item.title,
                                             target: .space(uuid: uuid, displayIdentifier: display.identifier)))
            }
        }
        return result
    }
}

private final class LabelView: NSView {
    var labels: [(CGRect, String)] = [] {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (frame, name) in labels {
            guard frame.intersects(dirtyRect) else { continue }
            NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let textRect = frame.insetBy(dx: 4, dy: 2)
            (name as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}

@MainActor
final class OverlayController {
    private var panels: [String: NSPanel] = [:]
    private var views: [String: LabelView] = [:]

    func show(_ placements: [LabelPlacement]) {
        let grouped = Dictionary(grouping: placements) { screenKey($0.screen) }
        for (key, panel) in panels where grouped[key] == nil {
            panel.orderOut(nil)
        }
        for (key, items) in grouped {
            guard let screen = items.first?.screen else { continue }
            let panel = panels[key] ?? makePanel(for: screen, key: key)
            panel.setFrame(screen.frame, display: false)
            views[key]?.frame = NSRect(origin: .zero, size: screen.frame.size)
            views[key]?.labels = items.compactMap { item in
                item.name.map { (item.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), $0) }
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panels.values.forEach { $0.orderOut(nil) }
    }

    private func makePanel(for screen: NSScreen, key: String) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .screenSaver
        let view = LabelView(frame: NSRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view
        panels[key] = panel
        views[key] = view
        return panel
    }

    private func screenKey(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
