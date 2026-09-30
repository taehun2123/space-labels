import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SpaceLabelsCore
import SwiftUI

struct RecoveryTarget {
    let uuid: String
    let displayIdentifier: String
    let title: String
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    @Published private(set) var snapshot: SpaceSnapshot?
    @Published private(set) var orphanedNames: [NameRecord] = []
    @Published private(set) var lastError: String?
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var overlayEnabled = true
    @Published private(set) var launchAtLogin = false
    @Published private(set) var savedWindowNames: [String: String] = [:]
    @Published private(set) var lastScanSummary = "Mission Control 화면을 아직 확인하지 않았습니다."
    @Published private(set) var lastClickSummary = "우클릭 입력을 아직 확인하지 않았습니다."

    private enum RenameTarget {
        case space(uuid: String, displayIdentifier: String, title: String)
        case window(key: String, persistent: Bool, title: String)

        var title: String {
            switch self {
            case let .space(_, _, title), let .window(_, _, title): return title
            }
        }
    }

    private let provider = SystemSpacesProvider()
    private let scanner = DockAXScanner()
    private let windowResolver = WindowIdentityResolver()
    private let overlay = OverlayController()
    private let worker = DispatchQueue(label: "local.spacelabels.observer", qos: .userInitiated)
    private var store: NameStore?
    private var windowStore: WindowNameStore?
    private var sessionWindowNames: [String: String] = [:]
    private var names: [String: String] = [:]
    private var ambiguousUUIDs: Set<String> = []
    private var placements: [LabelPlacement] = []
    private var lastPlacementDate = Date.distantPast
    private var rightClickMonitor: Any?
    private var rightClickTap: CFMachPort?
    private var rightClickTapSource: CFRunLoopSource?
    private var lastRightClickDate = Date.distantPast
    private var editorOpen = false
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindow: NSWindow?
    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var scanInFlight = false
    private var scanGeneration = 0

    var recoveryTargets: [RecoveryTarget] {
        guard let snapshot else { return [] }
        return snapshot.displays.enumerated().flatMap { displayIndex, display in
            display.spaces.enumerated().compactMap { index, space in
                guard let uuid = space.uuid, !names.keys.contains(uuid), !ambiguousUUIDs.contains(uuid) else { return nil }
                return RecoveryTarget(uuid: uuid, displayIdentifier: display.identifier,
                                      title: "\(displayTitle(display, number: displayIndex + 1)) · \(spaceTitle(space, in: display, index: index))")
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayEnabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? true
        accessibilityGranted = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.spacelabels", isDirectory: true)
        do {
            store = try NameStore(url: directory.appendingPathComponent("names.json"))
            windowStore = try WindowNameStore(url: directory.appendingPathComponent("window-names.json"))
            savedWindowNames = windowStore?.document.names ?? [:]
        } catch {
            lastError = "저장된 이름을 열지 못했습니다: \(error.localizedDescription)"
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.makeStatusIcon()
        item.button?.setAccessibilityLabel("Space Labels")
        statusItem = item
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        item.menu = menu

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.overlay.hide()
                self?.placements = []
                self?.refresh()
            }
        }
        pollingTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOverlay() }
        }
        if let pollingTimer { RunLoop.main.add(pollingTimer, forMode: .common) }
        installRightClickMonitor()
        refresh()
        if !launchAtLogin || store?.document.records.isEmpty == true { showSettings() }
    }

    private static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let backWindow = NSBezierPath(roundedRect: NSRect(x: 1.2, y: 8.0, width: 11.3, height: 7.8),
                                        xRadius: 1.5, yRadius: 1.5)
            backWindow.lineWidth = 1.4
            backWindow.stroke()

            let frontWindow = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.7, width: 11.7, height: 8.5),
                                         xRadius: 1.5, yRadius: 1.5)
            frontWindow.lineWidth = 1.4
            frontWindow.stroke()

            let label = NSBezierPath(roundedRect: NSRect(x: 10.1, y: 1.1, width: 6.5, height: 4.9),
                                     xRadius: 1.2, yRadius: 1.2)
            label.lineWidth = 1.4
            label.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTimer?.invalidate()
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        if let rightClickTap { CGEvent.tapEnable(tap: rightClickTap, enable: false) }
        if let rightClickTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), rightClickTapSource, .commonModes) }
        overlay.hide()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func refresh() {
        do {
            let latest = try provider.snapshot()
            snapshot = latest
            applyReconciliation(latest)
            if lastError?.hasPrefix("공간 조회") == true { lastError = nil }
        } catch {
            snapshot = nil
            names = [:]
            ambiguousUUIDs = []
            orphanedNames = store?.document.records ?? []
            lastError = "공간 조회 실패: \(error.localizedDescription)"
            overlay.hide()
            placements = []
        }
        accessibilityGranted = AXIsProcessTrusted()
        updateStatusTitle()
    }

    func name(for uuid: String) -> String? { names[uuid] }

    func spaceTitle(_ space: SystemSpace, in display: DisplaySnapshot, index: Int) -> String {
        if let number = DesktopLabel.number(for: space, in: display) { return "데스크톱 \(number)" }
        switch space.kind {
        case .application: return "전체 화면·Split View \(index + 1)"
        case .other: return "공간 \(index + 1)"
        case .desktop: return "데스크톱 \(index + 1)"
        }
    }

    func displayTitle(_ display: DisplaySnapshot, number: Int) -> String {
        if display.identifier == "Main" { return "주 디스플레이" }
        if let screen = ScreenResolver.screen(for: display.identifier) { return screen.localizedName }
        return "화면 \(number)"
    }

    func saveName(_ raw: String, uuid: String, display: String) {
        guard let store else { return }
        guard !ambiguousUUIDs.contains(uuid),
              snapshot?.displays.contains(where: { $0.identifier == display && $0.spaces.contains(where: { $0.uuid == uuid }) }) == true else {
            lastError = "편집하던 공간을 찾을 수 없습니다."
            return
        }
        do {
            try store.setName(raw, for: uuid, displayIdentifier: display)
            lastError = nil
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearName(uuid: String) {
        guard let store else { return }
        do {
            try store.clearName(for: uuid)
            lastError = nil
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearWindowName(key: String) {
        guard let windowStore else { return }
        do {
            try windowStore.clearName(for: key)
            savedWindowNames = windowStore.document.names
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func windowDescription(for key: String) -> String {
        let pieces = key.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
        return pieces.count == 2 ? "\(pieces[0]) · \(pieces[1])" : key
    }

    func reassign(recordID: UUID, to uuid: String) {
        guard let store, let target = recoveryTargets.first(where: { $0.uuid == uuid }) else { return }
        do {
            try store.reassign(recordID: recordID, to: uuid, displayIdentifier: target.displayIdentifier)
            lastError = nil
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setOverlayEnabled(_ enabled: Bool) {
        overlayEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "overlayEnabled")
        if !enabled {
            overlay.hide()
            placements = []
        }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        accessibilityGranted = AXIsProcessTrusted()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastError = launchAtLogin == enabled ? nil : "로그인 시 실행을 시스템 설정에서 승인하십시오."
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastError = error.localizedDescription
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        if let snapshot {
            for (displayIndex, display) in snapshot.displays.enumerated() {
                let title = NSMenuItem(title: displayTitle(display, number: displayIndex + 1), action: nil, keyEquivalent: "")
                title.isEnabled = false
                menu.addItem(title)
                for (index, space) in display.spaces.enumerated() {
                    let active = display.currentRuntimeID == space.runtimeID ? "● " : "   "
                    let name = space.uuid.flatMap { names[$0] }
                    let title = spaceTitle(space, in: display, index: index)
                    let row = NSMenuItem(title: "\(active)\(title)\(name.map { " · \($0)" } ?? "")",
                                         action: #selector(renameFromMenu(_:)), keyEquivalent: "")
                    row.target = self
                    row.isEnabled = space.uuid != nil && store != nil && !ambiguousUUIDs.contains(space.uuid ?? "")
                    if let uuid = space.uuid {
                        row.representedObject = RenameTarget.space(uuid: uuid, displayIdentifier: display.identifier,
                                                                    title: title)
                    }
                    menu.addItem(row)
                }
                if displayIndex < snapshot.displays.count - 1 { menu.addItem(.separator()) }
            }
        } else {
            let errorItem = NSMenuItem(title: lastError ?? "공간을 읽을 수 없습니다.", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "이름 및 설정…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if overlayEnabled && !accessibilityGranted {
            let permission = NSMenuItem(title: "접근성 권한 설정…", action: #selector(requestAccessibilityFromMenu), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        let quit = NSMenuItem(title: "Space Labels 종료", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func applyReconciliation(_ snapshot: SpaceSnapshot) {
        let reconciliation = Reconciliation(snapshot: snapshot, records: store?.document.records ?? [])
        names = reconciliation.names
        orphanedNames = reconciliation.orphaned
        ambiguousUUIDs = reconciliation.ambiguousUUIDs
    }

    private func updateStatusTitle() {
        guard let primary = snapshot?.displays.first(where: { $0.identifier == "Main" }),
              let active = primary.spaces.first(where: { $0.runtimeID == primary.currentRuntimeID }),
              let uuid = active.uuid else {
            statusItem?.button?.title = ""
            return
        }
        statusItem?.button?.title = names[uuid].map { " \($0)" } ?? ""
    }

    private func pollOverlay() {
        guard overlayEnabled, !editorOpen else { return }
        let trusted = AXIsProcessTrusted()
        if accessibilityGranted != trusted { accessibilityGranted = trusted }
        guard trusted else {
            scanGeneration += 1
            overlay.hide()
            placements = []
            lastScanSummary = "접근성 권한이 적용되지 않았습니다. 권한을 확인한 뒤 앱을 다시 여십시오."
            return
        }
        guard !scanInFlight else { return }
        scanInFlight = true
        scanGeneration += 1
        let generation = scanGeneration
        let provider = self.provider
        let scanner = self.scanner
        let windowResolver = self.windowResolver
        worker.async { [weak self] in
            let latest = try? provider.snapshot()
            let scan = scanner.scan()
            let resolvedWindows = scan.map { windowResolver.resolve($0.windows) } ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanInFlight = false
                guard self.scanGeneration == generation,
                      self.overlayEnabled,
                      let scan,
                      let latest else {
                    self.overlay.hide()
                    self.placements = []
                    self.sessionWindowNames = self.sessionWindowNames.filter { !$0.key.hasPrefix("session:unresolved:") }
                    return
                }
                self.snapshot = latest
                self.applyReconciliation(latest)
                self.updateStatusTitle()
                let spacePlacements = OverlayMatcher.placements(snapshot: latest, names: self.names,
                                                                items: scan.spaces, ambiguousUUIDs: self.ambiguousUUIDs)
                let windowPlacements = WindowOverlayMatcher.placements(windows: resolvedWindows,
                                                                       persistentNames: self.savedWindowNames,
                                                                       sessionNames: self.sessionWindowNames)
                let placements = spacePlacements + windowPlacements
                self.lastScanSummary = "최근 인식: 공간 \(scan.spaces.count)개 중 \(spacePlacements.count)개, 앱 창 \(scan.windows.count)개 중 \(windowPlacements.count)개 편집 가능"
                self.placements = placements
                self.lastPlacementDate = Date()
                self.overlay.show(placements)
            }
        }
    }

    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Space Labels"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(app: self))
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installRightClickMonitor() {
        let mask = CGEventMask(1) << CGEventType.rightMouseDown.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                       options: .listenOnly, eventsOfInterest: mask,
                                       callback: Self.eventTapCallback, userInfo: context) {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            rightClickTap = tap
            rightClickTapSource = source
            lastClickSummary = "우클릭 감시가 준비되었습니다."
        } else {
            lastClickSummary = "우클릭 감시를 시작하지 못했습니다. 입력 모니터링 권한을 확인하십시오."
        }
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.renameAtMouseLocation(point) }
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, context in
        if type == .tapDisabledByTimeout, let context {
            let app = Unmanaged<AppController>.fromOpaque(context).takeUnretainedValue()
            if let tap = app.rightClickTap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else if type == .rightMouseDown, let context {
            let app = Unmanaged<AppController>.fromOpaque(context).takeUnretainedValue()
            let point = ScreenResolver.appKitPoint(fromAX: event.location)
            Task { @MainActor in app.renameAtMouseLocation(point) }
        }
        return Unmanaged.passUnretained(event)
    }

    @objc private func renameFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? RenameTarget else { return }
        showRenameEditor(for: target)
    }

    private func renameAtMouseLocation(_ point: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastRightClickDate) >= 0.2 else { return }
        lastRightClickDate = now
        guard overlayEnabled, !editorOpen else { return }
        guard now.timeIntervalSince(lastPlacementDate) < 10 else {
            lastClickSummary = "우클릭은 감지했지만 Mission Control 항목 위치가 오래되었습니다."
            return
        }
        let hits = placements.filter { $0.hitFrame.contains(point) }
        guard hits.count == 1, let hit = hits.first else {
            lastClickSummary = "우클릭은 감지했지만 해당 위치에 편집할 공간이나 창을 찾지 못했습니다."
            return
        }
        lastClickSummary = "우클릭한 \(hit.title) 항목의 이름 입력창을 열었습니다."
        switch hit.target {
        case let .space(uuid, displayIdentifier):
            showRenameEditor(for: .space(uuid: uuid, displayIdentifier: displayIdentifier, title: hit.title))
        case let .window(key, persistent):
            showRenameEditor(for: .window(key: key, persistent: persistent, title: hit.title))
        }
    }

    private func showRenameEditor(for target: RenameTarget) {
        guard !editorOpen else { return }
        editorOpen = true
        overlay.hide()
        let alert = NSAlert()
        alert.messageText = "\(target.title) 이름"
        alert.informativeText = "새 이름을 입력하십시오. 40자까지 사용할 수 있습니다."
        if case let .window(key, false, _) = target {
            alert.informativeText += key.hasPrefix("session:unresolved:")
                ? " 이 창은 고유한 식별자를 확인할 수 없어 Mission Control 화면을 닫으면 이름을 지웁니다."
                : " 이 창은 이번 앱 실행에서만 이름을 유지합니다."
        }
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        let existing: String
        switch target {
        case let .space(uuid, _, _): existing = name(for: uuid) ?? ""
        case let .window(key, persistent, _):
            existing = persistent ? (savedWindowNames[key] ?? "") : (sessionWindowNames[key] ?? "")
        }
        let field = NSTextField(string: existing)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        editorOpen = false
        placements = []
        if response == .alertFirstButtonReturn {
            switch target {
            case let .space(uuid, display, _):
                saveName(field.stringValue, uuid: uuid, display: display)
            case let .window(key, persistent, _):
                do {
                    let name = try NameRules.validated(field.stringValue)
                    if persistent, let windowStore {
                        try windowStore.setName(name, for: key)
                        savedWindowNames = windowStore.document.names
                    } else {
                        sessionWindowNames[key] = name
                    }
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if let lastError {
                let failure = NSAlert()
                failure.messageText = "이름을 저장하지 못했습니다."
                failure.informativeText = lastError
                failure.runModal()
            }
        }
    }

    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func requestAccessibilityFromMenu() { requestAccessibility() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
}
