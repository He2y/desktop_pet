import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let spriteStore = try SpriteStore()
            let controller = PetController(spriteStore: spriteStore)
            self.controller = controller
            configureStatusItem(controller: controller)
            controller.start()
        } catch {
            presentStartupError(error)
            NSApp.terminate(nil)
        }
    }

    private func configureStatusItem(controller: PetController) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Pet"

        item.menu = controller.makeMenu()
        statusItem = item
    }

    private func presentStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Desktop Pet could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
