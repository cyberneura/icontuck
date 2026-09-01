import AppKit

/// Implements the "Level 1" tuck technique.
///
/// A deliberately oversized status item consumes menu bar space and pushes every
/// item to its *left* beyond the visible screen edge. Tahoe clamps the requested
/// 10,000 pt width to roughly 5,000 pt, which still exceeds any menu bar width.
///
/// Because only items to the left move, the oversized item has to be inserted
/// immediately to the left of the control item. Anywhere further right and the
/// control item is pushed off screen too, leaving the app unclickable.
@MainActor
final class SeparatorManager {
    static let requestedLength: CGFloat = 10_000

    private static let autosaveName = "IcontuckSeparator"

    private var separatorItem: NSStatusItem?

    var isInstalled: Bool { separatorItem != nil }

    func setVisible(_ visible: Bool, anchoredTo anchorName: String) {
        if visible {
            install(anchoredTo: anchorName)
        } else {
            remove()
        }
    }

    /// Recreating the item re-reads the anchor's slot, which the user can move by
    /// Command-dragging the control icon.
    func refreshPlacement(anchoredTo anchorName: String) {
        guard separatorItem != nil else { return }
        remove()
        install(anchoredTo: anchorName)
    }

    private func install(anchoredTo anchorName: String) {
        guard separatorItem == nil else { return }

        if let anchorSlot = StatusItemSlot.value(for: anchorName) {
            StatusItemSlot.set(anchorSlot + 1, for: Self.autosaveName)
        }

        let item = NSStatusBar.system.statusItem(withLength: Self.requestedLength)
        item.autosaveName = Self.autosaveName

        if let button = item.button {
            button.title = ""
            button.image = separatorImage()
            button.imagePosition = .imageTrailing
            button.imageScaling = .scaleNone
            button.alignment = .right
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

/// AppKit persists the slot of every status item under this defaults key and keeps
/// it up to date as the user Command-drags items around.
///
/// This is not a private API call, but it is not a documented contract either.
/// Apple documents that `autosaveName` makes a status item remember its position;
/// the key's spelling and the meaning of the number are observed behaviour and
/// can change in a macOS release. The two failure modes are not equally benign:
/// if the key stops being honoured the separator lands where AppKit parks any new
/// item — at the far left, tucking nothing — but if the ordering the number
/// expresses were reversed, `anchorSlot + 1` would place the separator to the
/// *right* of the control item and push it off screen, leaving an agent app with
/// no icon to click and no Dock entry to quit from. Nothing detects that today.
///
/// The number is not a screen coordinate: items are sorted by it and then packed
/// against the right edge, so only the relative ordering matters. Deriving the
/// separator's slot from the anchor's stored value — rather than from either item's
/// on-screen frame — is what keeps other apps from sorting in between the two.
enum StatusItemSlot {
    static func value(for autosaveName: String) -> Double? {
        (UserDefaults.standard.object(forKey: key(for: autosaveName)) as? NSNumber)?.doubleValue
    }

    static func set(_ value: Double, for autosaveName: String) {
        UserDefaults.standard.set(value, forKey: key(for: autosaveName))
    }

    static func setIfMissing(_ value: Double, for autosaveName: String) {
        guard UserDefaults.standard.object(forKey: key(for: autosaveName)) == nil else { return }
        set(value, for: autosaveName)
    }

    private static func key(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }
}
