import Foundation

/// Pure, AppKit-free helpers for the native tab container.
///
/// Kept free of `NSView`/`NSColor` so `--self-test` can exercise the URL
/// rewriting, close/neighbour arithmetic and new-tab URL composition without a
/// GUI. `AppWindowController` and the self-test share exactly this logic.
enum TabSupport {
    /// Replaces the scheme/host/port of `url` with those of `base`, preserving
    /// the original path, query and fragment. Returns `url` unchanged when
    /// either string fails to parse.
    static func rewriteBase(_ url: String, to base: String) -> String {
        guard var components = URLComponents(string: url),
              let baseComponents = URLComponents(string: base) else {
            return url
        }
        components.scheme = baseComponents.scheme
        components.host = baseComponents.host
        components.port = baseComponents.port
        return components.string ?? url
    }

    /// The index to select after closing the tab at `closed`, where `count` is
    /// the number of tabs *before* the close. Returns `nil` when that was the
    /// last tab (the caller hides the window instead).
    static func indexAfterClose(closed: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        return max(0, min(closed, count - 2))
    }

    /// The wrapped neighbour of `current`, e.g. `(2, 3, +1) -> 0`. An empty
    /// set always yields `0`.
    static func neighborIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = (current + delta) % count
        return raw < 0 ? raw + count : raw
    }

    /// The URL a manually created tab should load: the session list scoped to
    /// the active tab's `cwd` when it has one, otherwise the unscoped list.
    /// Never creates or mutates a session server-side.
    static func newTabURL(base: String, activeURL: String?) -> String {
        if let activeURL,
           let components = URLComponents(string: activeURL),
           let cwd = components.queryItems?.first(where: { $0.name == "cwd" })?.value,
           !cwd.isEmpty {
            return base + "/?cwd=" + encodeQueryValue(cwd)
        }
        return base + "/"
    }

    /// Percent-encodes a query value, including `/`, so a filesystem path is
    /// safe inside `?cwd=` on every server/browser.
    private static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
