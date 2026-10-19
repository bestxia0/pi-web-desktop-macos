import Foundation
import ServiceManagement

/// "Start at Login" via SMAppService.mainApp (macOS 13+).
///
/// SMAppService requires the app to live in a stable location (/Applications
/// or ~/Applications). When the bundle is elsewhere, `register()` fails; the
/// menu then reflects the real status instead of pretending success.
enum LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notFound
        case unavailable(String)
    }

    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static func currentState() -> State {
        guard #available(macOS 13.0, *) else {
            return .unavailable("需要 macOS 13+")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    static func isEnabled() -> Bool {
        currentState() == .enabled
    }

    /// Returns nil on success, or a human-readable reason on failure.
    static func setEnabled(_ enabled: Bool) -> String? {
        guard #available(macOS 13.0, *) else {
            return "Start at Login 需要 macOS 13+"
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            let reason = error.localizedDescription
            Logger.shared.error("login item \(enabled ? "register" : "unregister") failed: \(reason)")
            return reason
        }
    }
}
