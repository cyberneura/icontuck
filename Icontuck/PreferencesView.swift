import SwiftUI
import ServiceManagement

enum PreferenceKey {
    static let showSeparator = "showSeparator"
    static let autoHideWhenInactive = "autoHideWhenInactive"
}

extension Notification.Name {
    static let icontuckPreferencesChanged = Notification.Name("IcontuckPreferencesChanged")
}

struct PreferencesView: View {
    @AppStorage(PreferenceKey.showSeparator) private var showSeparator = true
    @AppStorage(PreferenceKey.autoHideWhenInactive) private var autoHideWhenInactive = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: updateLaunchAtLogin
            ))
            Toggle("Show separator", isOn: $showSeparator)
            Toggle("Auto-hide when inactive", isOn: $autoHideWhenInactive)

            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 420, height: 190)
        .onChange(of: showSeparator) { _, _ in notifyChanged() }
        .onChange(of: autoHideWhenInactive) { _, _ in notifyChanged() }
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

