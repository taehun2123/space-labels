import AppKit

@main
struct SpaceLabelsMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
