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

    static let hotKeyEnabledKey = "PiWebHotKeyEnabled"
    static let defaultHotKeyEnabled = true

    /// Defaults to ON when the key has never been written.
    static func hotKeyEnabled(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: hotKeyEnabledKey) == nil {
            return defaultHotKeyEnabled
        }
        return defaults.bool(forKey: hotKeyEnabledKey)
    }

    static func setHotKeyEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: hotKeyEnabledKey)
    }

    static var hotKeyEnabled: Bool {
        get { hotKeyEnabled(from: .standard) }
        set { setHotKeyEnabled(newValue, in: .standard) }
    }
}
