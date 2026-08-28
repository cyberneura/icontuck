import AppKit
import SwiftUI
import ServiceManagement

#if canImport(Sparkle) && SPARKLE_ENABLED
import Sparkle
#endif

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlItem: NSStatusItem!
    private let separatorManager = SeparatorManager()
    private var preferencesWindowController: NSWindowController?
    private var activityObservers: [NSObjectProtocol] = []

#if canImport(Sparkle) && SPARKLE_ENABLED
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.showSeparator: true,
            PreferenceKey.autoHideWhenInactive: false
        ])

        configureControlItem()
        separatorManager.setVisible(UserDefaults.standard.bool(forKey: PreferenceKey.showSeparator))
        observePreferences()
        observeApplicationActivity()

#if canImport(Sparkle) && SPARKLE_ENABLED
        _ = updaterController
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func configureControlItem() {
        controlItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = controlItem.button else { return }

        button.image = NSImage(systemSymbolName: "rectangle.leadinghalf.inset.filled", accessibilityDescription: "Icontuck")
        button.image?.isTemplate = true
        button.toolTip = "Icontuck"

        let menu = NSMenu()
        let toggleItem = menu.addItem(withTitle: "Show/Hide Separator", action: #selector(toggleSeparator), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(.separator())
        let preferencesItem = menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Icontuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        controlItem.menu = menu
    }

    private func observePreferences() {
        NotificationCenter.default.addObserver(
            forName: .icontuckPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySeparatorPreference()
        }
    }

    private func observeApplicationActivity() {
        let center = NotificationCenter.default
        activityObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard UserDefaults.standard.bool(forKey: PreferenceKey.autoHideWhenInactive) else { return }
            self?.separatorManager.setVisible(false)
        })
        activityObservers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySeparatorPreference()
        })
    }

    private func applySeparatorPreference() {
        let defaults = UserDefaults.standard
        let shouldShow = defaults.bool(forKey: PreferenceKey.showSeparator)
        let autoHide = defaults.bool(forKey: PreferenceKey.autoHideWhenInactive)
        separatorManager.setVisible(shouldShow && (!autoHide || NSApp.isActive))
    }

    @objc private func toggleSeparator() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: PreferenceKey.showSeparator), forKey: PreferenceKey.showSeparator)
        applySeparatorPreference()
        NotificationCenter.default.post(name: .icontuckPreferencesChanged, object: nil)
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            let hostingController = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Icontuck Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 190))
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
