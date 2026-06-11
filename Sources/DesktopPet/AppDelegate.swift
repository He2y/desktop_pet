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

        let menu = NSMenu()
        menu.addItem(withTitle: "Return to Dock", action: #selector(PetController.returnToDock), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Eat", action: #selector(PetController.eatNow), keyEquivalent: "")
        menu.addItem(withTitle: "Drag Pose", action: #selector(PetController.dragPreviewNow), keyEquivalent: "")
        menu.addItem(withTitle: "Scratch", action: #selector(PetController.scratchNow), keyEquivalent: "")
        menu.addItem(withTitle: "Teaser", action: #selector(PetController.teaserNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Right", action: #selector(PetController.walkRightNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Left", action: #selector(PetController.walkLeftNow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desktop Pet", action: #selector(PetController.quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = controller
        }

        item.menu = menu
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
