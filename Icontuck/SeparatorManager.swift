import AppKit

/// Implements the public-API-only "Level 1" separator technique.
///
/// A deliberately oversized status item consumes the available status-bar space,
/// pushing items to its left beyond the visible screen edge. Tahoe may clamp the
/// requested 10,000 pt width to roughly 5,016 pt, and may initially park the item
/// near x = -4,220 when the menu bar is already full. Recreating the item on show
/// lets AppKit recalculate its placement without relying on private APIs.
@MainActor
final class SeparatorManager {
    static let requestedLength: CGFloat = 10_000

    private var separatorItem: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible {
            installIfNeeded()
        } else {
            remove()
        }
    }

    private func installIfNeeded() {
        guard separatorItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: Self.requestedLength)
        item.autosaveName = "IcontuckSeparator"

        if let button = item.button {
            button.title = ""
            button.image = separatorImage()
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleNone
            button.isEnabled = false
            button.toolTip = "Icontuck separator"
        }

        separatorItem = item
    }

    private func remove() {
        guard let separatorItem else { return }
        NSStatusBar.system.removeStatusItem(separatorItem)
        self.separatorItem = nil
    }

    private func separatorImage() -> NSImage {
        let size = NSSize(width: 7, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.separatorColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 2, width: 1, height: rect.height - 4), xRadius: 0.5, yRadius: 0.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

