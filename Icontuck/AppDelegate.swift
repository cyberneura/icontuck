import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let controlAutosaveName = "IcontuckControl"

    /// Keeps the control icon to a bare glyph; the default square length reserves
    /// noticeably more menu bar width than the chevron needs.
    private static let controlLength: CGFloat = 12

    private var controlItem: NSStatusItem!
    private let separatorManager = SeparatorManager()
    private var preferencesWindowController: NSWindowController?
    private var observers: [NSObjectProtocol] = []
    private var followsDisplayConfiguration = false
    private lazy var contextMenu = makeContextMenu()
    private var toggleMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            PreferenceKeys.iconsHidden: false,
            PreferenceKeys.followDisplayConfiguration: false
        ])
        followsDisplayConfiguration = defaults.bool(forKey: PreferenceKeys.followDisplayConfiguration)

        configureControlItem()
        applyDisplayConfigurationRule()
        applyHiddenState()
        observePreferences()
        observeScreenChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Status item

    private func configureControlItem() {
        // AppKit parks a brand new status item at the far left of the third-party
        // group, where nothing sits to its left and so nothing can be tucked.
        // Seeding the slot once puts the control at the right end of that group,
        // which makes the first click hide every third-party icon.
        StatusItemSlot.setIfMissing(0, for: Self.controlAutosaveName)

        controlItem = NSStatusBar.system.statusItem(withLength: Self.controlLength)
        controlItem.autosaveName = Self.controlAutosaveName
        guard let button = controlItem.button else { return }

        button.target = self
        button.action = #selector(handleControlClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleItem = menu.addItem(withTitle: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        toggleMenuItem = toggleItem
        menu.addItem(.separator())
        let preferencesItem = menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Icontuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        return menu
    }

    @objc private func handleControlClick() {
        // Accessibility presses arrive without a current event; those toggle.
        let isSecondaryClick = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false
        if isSecondaryClick {
            presentContextMenu()
        } else {
            setIconsHidden(!UserDefaults.standard.bool(forKey: PreferenceKeys.iconsHidden))
        }
    }

    /// The menu is attached only for the duration of a secondary click; leaving it
    /// attached makes AppKit open it on primary clicks instead of sending the
    /// action, which is what the toggle needs.
    private func presentContextMenu() {
        controlItem.menu = contextMenu
        controlItem.button?.performClick(nil)
        controlItem.menu = nil
    }

    @objc private func toggleFromMenu() {
        setIconsHidden(!UserDefaults.standard.bool(forKey: PreferenceKeys.iconsHidden))
    }

    // MARK: - State

    private func setIconsHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: PreferenceKeys.iconsHidden)
        applyHiddenState()
    }

    private func applyHiddenState() {
        let hidden = UserDefaults.standard.bool(forKey: PreferenceKeys.iconsHidden)

        if hidden && separatorManager.isInstalled {
            separatorManager.refreshPlacement(anchoredTo: Self.controlAutosaveName)
        } else {
            separatorManager.setVisible(hidden, anchoredTo: Self.controlAutosaveName)
        }

        updateControlAppearance(hidden: hidden)
        updateContextMenu()
    }

    private func updateControlAppearance(hidden: Bool) {
        guard let button = controlItem?.button else { return }
        let symbol = hidden ? "chevron.right" : "chevron.left"
        let description = hidden ? "Show menu bar icons" : "Hide menu bar icons"
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = hidden ? "›" : "‹"
        }
        button.toolTip = description
    }

    private var toggleTitle: String {
        UserDefaults.standard.bool(forKey: PreferenceKeys.iconsHidden)
            ? "Show Icons"
            : "Hide Icons to the Left"
    }

    /// No-op until the menu has been built. `makeContextMenu` therefore sets the
    /// title itself rather than relying on a later update, so the item is never
    /// shown blank on the first secondary click.
    private func updateContextMenu() {
        toggleMenuItem?.title = toggleTitle
    }

    // MARK: - Observers

    private func observePreferences() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .icontuckPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePreferencesChanged()
            }
        })
    }

    private func handlePreferencesChanged() {
        let follows = UserDefaults.standard.bool(forKey: PreferenceKeys.followDisplayConfiguration)
        if follows != followsDisplayConfiguration {
            followsDisplayConfiguration = follows
            applyDisplayConfigurationRule()
        }
        applyHiddenState()
    }

    private func observeScreenChanges() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyDisplayConfigurationRule()
                self?.applyHiddenState()
            }
        })
    }

    // MARK: - Display configuration

    /// A status item lives on whichever screen currently owns the menu bar, so
    /// per-display visibility is not expressible. The rule keys off the set of
    /// attached displays instead: tuck while only the built-in panel is present.
    ///
    /// It runs at launch and whenever displays change, not continuously, so a
    /// click still overrides the result until the next display change. Enforcing
    /// it on every state change would make the icon unclickable on a laptop with
    /// no external display.
    private func applyDisplayConfigurationRule() {
        guard followsDisplayConfiguration else { return }
        UserDefaults.standard.set(!hasExternalDisplay, forKey: PreferenceKeys.iconsHidden)
    }

    private var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }

    // MARK: - Preferences window

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            let hostingController = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Icontuck Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 250))
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

/// AppKit only wires a delegate through a MainMenu nib, and this app ships none,
/// so the delegate is assigned explicitly before the run loop starts.
@main
enum IcontuckMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        // NSApplication.delegate is a weak reference, so this is the only thing
        // keeping the delegate alive for the lifetime of the run loop.
        withExtendedLifetime(delegate) {}
    }
}
