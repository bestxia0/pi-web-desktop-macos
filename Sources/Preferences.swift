import Foundation

/// User-facing preferences persisted in UserDefaults (bundle domain
/// `com.piweb.desktop`).
enum Preferences {
    static let stopAttachedOnQuitKey = "PiWebStopAttachedOnQuit"
    static let defaultStopAttachedOnQuit = true

    /// Defaults to ON when the key has never been written.
    static func stopAttachedOnQuit(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: stopAttachedOnQuitKey) == nil {
            return defaultStopAttachedOnQuit
        }
        return defaults.bool(forKey: stopAttachedOnQuitKey)
    }

    static func setStopAttachedOnQuit(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: stopAttachedOnQuitKey)
    }

    static var stopAttachedOnQuit: Bool {
        get { stopAttachedOnQuit(from: .standard) }
        set { setStopAttachedOnQuit(newValue, in: .standard) }
    }
}
