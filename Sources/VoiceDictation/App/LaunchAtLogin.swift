import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` so "Launch at Login" is a one-liner.
/// No-ops gracefully if the app isn't a registered bundle (e.g. run from the
/// build dir during development).
enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin: \(error.localizedDescription)")
        }
    }
}
