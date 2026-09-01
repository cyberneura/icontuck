import SwiftUI
import ServiceManagement

/// Named `PreferenceKeys` because `PreferenceKey` collides with the SwiftUI
/// protocol of that name and leaves the editor resolving every use to it.
enum PreferenceKeys {
    static let iconsHidden = "iconsHidden"
    static let followDisplayConfiguration = "followDisplayConfiguration"
}

extension Notification.Name {
    static let icontuckPreferencesChanged = Notification.Name("IcontuckPreferencesChanged")
}

struct PreferencesView: View {
    @AppStorage(PreferenceKeys.iconsHidden) private var iconsHidden = false
    @AppStorage(PreferenceKeys.followDisplayConfiguration) private var followDisplayConfiguration = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Hide icons", isOn: $iconsHidden)
                Text("Icons to the left of the Icontuck icon are tucked off screen. Command-drag the Icontuck icon to move the boundary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hide when only the built-in display is connected", isOn: $followDisplayConfiguration)
                Text("Applied at launch and whenever a display is attached or removed. Clicking the icon overrides it until the next change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: updateLaunchAtLogin
                ))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 420, height: 250)
        .onChange(of: iconsHidden) { _, _ in notifyChanged() }
        .onChange(of: followDisplayConfiguration) { _, _ in notifyChanged() }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .icontuckPreferencesChanged, object: nil)
    }
}

#Preview {
    PreferencesView()
}
