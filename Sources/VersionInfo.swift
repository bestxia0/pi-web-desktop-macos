import Foundation

/// The launcher's own version, shown at the bottom of the menu bar menu.
///
/// Single source of truth: `build.sh` reads the repository's `VERSION` file and
/// the current date, then writes `PiWebVersion` (e.g. `0.5.0-20261019`) plus
/// `CFBundleShortVersionString` into Info.plist. Nothing here hardcodes a
/// release number, so a version bump is one file plus a rebuild.
enum VersionInfo {
    /// Custom key written by `build.sh`; the full `<semantic>-<YYYYMMDD>`.
    static let plistKey = "PiWebVersion"
    /// Standard key, used as a fallback and by any future update check.
    static let semanticPlistKey = "CFBundleShortVersionString"
    /// Used when neither key can be read (a raw binary outside a bundle).
    static let fallback = "0.0.0-dev"

    /// `<semantic>-<date>`; an empty date means a development build.
    static func compose(semantic: String, date: String) -> String {
        let version = semantic.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = date.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.isEmpty { return stamp.isEmpty ? fallback : stamp }
        return stamp.isEmpty ? "\(version)-dev" : "\(version)-\(stamp)"
    }

    /// What the menu shows: the composed version behind a `V`.
    static func display(raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return "V\(value.isEmpty ? fallback : value)"
    }

    /// `PiWebVersion`, else `CFBundleShortVersionString`, else the fallback.
    static var rawVersion: String {
        for key in [plistKey, semanticPlistKey] {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallback
    }

    /// The exact string the menu's version row shows, also printed by `--version`.
    static var displayVersion: String { display(raw: rawVersion) }
}
