import AppKit

final class PetView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var dragStartInScreen: CGPoint?
    private var dragWindowOrigin: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartInScreen = NSEvent.mouseLocation
        dragWindowOrigin = window?.frame.origin
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartInScreen, let dragWindowOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - dragStartInScreen.x, y: current.y - dragStartInScreen.y)
        onDragged?(CGPoint(x: dragWindowOrigin.x + delta.x, y: dragWindowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartInScreen = nil
        dragWindowOrigin = nil
        onDragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .high

        let target = aspectFitRect(imageSize: image.size, in: bounds)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        postsFrameChangedNotifications = true
    }

    private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}
