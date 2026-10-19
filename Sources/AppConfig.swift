import Foundation

/// Central constants and path/agent-directory resolution.
///
/// The agent directory resolution mirrors pi-web's `bin/run-records.js`
/// `getAgentDir()` exactly, so this shell reads the same run records pi-web
/// itself writes.
enum AppConfig {
    static let defaultPort = 30141
    static let fallbackPortBase = 30151
    static let hostname = "127.0.0.1"
    static let bundleIdentifier = "com.piweb.desktop"
    static let appName = "Pi Web"

    /// Overrides the preferred port. Set from `--port` / `PI_WEB_DESKTOP_PORT`,
    /// mainly for tests that must not touch the real 30141.
    static var preferredPortOverride: Int?

    static var preferredPort: Int { preferredPortOverride ?? defaultPort }

    static var homeDirectory: String {
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// `PI_CODING_AGENT_DIR` expanded (`~`, `~/`, `file://`), else `~/.pi/agent`.
    static func agentDir(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        guard let configured = env["PI_CODING_AGENT_DIR"], !configured.isEmpty else {
            return (homeDirectory as NSString).appendingPathComponent(".pi/agent")
        }
        return expandAgentDir(configured, home: homeDirectory)
    }

    static func expandAgentDir(_ configured: String, home: String) -> String {
        if configured == "~" { return home }
        if configured.hasPrefix("~/") || configured.hasPrefix("~\\") {
            return (home as NSString).appendingPathComponent(String(configured.dropFirst(2)))
        }
        if configured.hasPrefix("file://") {
            if let url = URL(string: configured), !url.path.isEmpty {
                return url.path
            }
        }
        return configured
    }

    static func runDir(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        (agentDir(env: env) as NSString).appendingPathComponent("pi-web-run")
    }

    static var logDirectory: String {
        (homeDirectory as NSString).appendingPathComponent("Library/Logs/PiWeb")
    }

    static var logFile: String {
        (logDirectory as NSString).appendingPathComponent("pi-web.log")
    }

    static var supportDirectory: String {
        (homeDirectory as NSString).appendingPathComponent("Library/Application Support/PiWeb")
    }

    static var lockFile: String {
        (supportDirectory as NSString).appendingPathComponent("launcher.lock")
    }

    static func url(port: Int, host: String = AppConfig.hostname) -> String {
        "http://\(host):\(port)"
    }
}
