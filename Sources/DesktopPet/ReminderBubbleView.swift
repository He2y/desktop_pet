import AppKit

final class ReminderBubbleView: NSView {
    private static let maxBubbleWidth: CGFloat = 280
    private static let minBubbleWidth: CGFloat = 172
    private static let horizontalPadding: CGFloat = 18
    private static let verticalPadding: CGFloat = 12
    private static let tailHeight: CGFloat = 10

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func update(message: String) -> CGSize {
        label.stringValue = message

        let maxTextWidth = Self.maxBubbleWidth - Self.horizontalPadding * 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font ?? NSFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        let textRect = (message as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let width = min(
            Self.maxBubbleWidth,
            max(Self.minBubbleWidth, ceil(textRect.width) + Self.horizontalPadding * 2)
        )
        let height = ceil(textRect.height) + Self.verticalPadding * 2 + Self.tailHeight
        label.frame = CGRect(
            x: Self.horizontalPadding,
            y: Self.tailHeight + Self.verticalPadding,
            width: width - Self.horizontalPadding * 2,
            height: ceil(textRect.height) + 2
        )

        frame = CGRect(origin: frame.origin, size: CGSize(width: width, height: height))
        needsDisplay = true
        return frame.size
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: -3)
        shadow.set()

        var bubbleRect = bounds.insetBy(dx: 1, dy: 1)
        bubbleRect.origin.y += Self.tailHeight
        bubbleRect.size.height -= Self.tailHeight
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 16, yRadius: 16)
        NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
        bubblePath.fill()

        let tailCenterX = min(max(bounds.midX, bubbleRect.minX + 34), bubbleRect.maxX - 34)
        let tailPath = NSBezierPath()
        tailPath.move(to: CGPoint(x: tailCenterX - 11, y: bubbleRect.minY + 1))
        tailPath.line(to: CGPoint(x: tailCenterX, y: bounds.minY + 1))
        tailPath.line(to: CGPoint(x: tailCenterX + 11, y: bubbleRect.minY + 1))
        tailPath.close()
        tailPath.fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0, alpha: 0.08).setStroke()
        bubblePath.lineWidth = 1
        bubblePath.stroke()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.12, alpha: 1)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.alignment = .center
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }
}
