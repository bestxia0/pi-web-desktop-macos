import Foundation
import Darwin

/// Result of asking the login shell for `pi-web` and `PATH`.
struct LoginProbe {
    let piWeb: String?
    let path: String?
}

/// Resolves an environment that works when the app was launched by
/// LaunchServices (which gives only `/usr/bin:/bin:/usr/sbin:/sbin`).
///
/// Two independent things are needed:
///  1. locating the `pi-web` executable (homebrew lives in /opt/homebrew/bin);
///  2. a PATH for the *child* process that also contains `node`, because
///     pi-web is a `#!/usr/bin/env node` script.
enum EnvironmentResolver {
    static let systemDefaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    static var knownBinDirectories: [String] {
        [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "~/.local/bin",
            "~/.bun/bin",
            "~/.npm-global/bin",
        ].map(expandTilde)
    }

    static func expandTilde(_ path: String) -> String {
        if path == "~" { return AppConfig.homeDirectory }
        if path.hasPrefix("~/") {
            return (AppConfig.homeDirectory as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return path
    }

    // MARK: - Login shell probe

    /// Asks the login shell once: `/bin/zsh -lic '<command -v pi-web; echo PATH>'`.
    /// Hard 5s timeout so a slow `.zshrc` cannot hang app startup.
    static func loginShellProbe(timeout: TimeInterval = 5) -> LoginProbe? {
        let script = "printf 'PIWEB_PATH=%s\\n' \"$(command -v pi-web 2>/dev/null)\"; "
            + "printf 'LOGIN_PATH=%s\\n' \"$PATH\""
        guard let output = runProcess("/bin/zsh", ["-lic", script], timeout: timeout) else {
            return nil
        }
        let probe = parseProbeOutput(output)
        if probe.path == nil && probe.piWeb == nil { return nil }
        return probe
    }

    /// Parses the marker lines out of the login shell output, ignoring noise
    /// that rc files may print to stdout.
    static func parseProbeOutput(_ output: String) -> LoginProbe {
        var piWeb: String?
        var path: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("PIWEB_PATH=") {
                let value = String(line.dropFirst("PIWEB_PATH=".count))
                piWeb = value.isEmpty ? nil : value
            } else if line.hasPrefix("LOGIN_PATH=") {
                let value = String(line.dropFirst("LOGIN_PATH=".count))
                path = value.isEmpty ? nil : value
            }
        }
        return LoginProbe(piWeb: piWeb, path: path)
    }

    // MARK: - Child PATH

    /// The PATH to inject into the spawned pi-web: the login shell's PATH when
    /// available, otherwise known bin directories + node dirs + system default.
    static func effectivePATH(loginPATH: String?, env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var parts: [String] = []
        if let loginPATH, !loginPATH.isEmpty {
            parts.append(contentsOf: splitPATH(loginPATH))
        }
        parts.append(contentsOf: knownBinDirectories)
        parts.append(contentsOf: discoverNodeDirectories())
        if loginPATH == nil, let npm = npmGlobalBin(env: env) {
            parts.append(npm)
        }
        if let current = env["PATH"], !current.isEmpty {
            parts.append(contentsOf: splitPATH(current))
        }
        parts.append(contentsOf: splitPATH(systemDefaultPath))
        return mergePaths(parts)
    }

    static func splitPATH(_ path: String) -> [String] {
        path.split(separator: ":").map(String.init)
    }

    /// De-duplicates while preserving order and drops empties.
    static func mergePaths(_ parts: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for raw in parts {
            let value = raw.trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            if seen.insert(value).inserted { out.append(value) }
        }
        return out.joined(separator: ":")
    }

    /// Directories that actually contain a `node` executable.
    static func discoverNodeDirectories() -> [String] {
        var candidates: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
        candidates.append(contentsOf: glob("/opt/homebrew/opt/node*/bin"))
        candidates.append(contentsOf: glob(expandTilde("~/.nvm/versions/node/*/bin")))
        return candidates.filter { hasExecutable("node", in: $0) }
    }

    static func containsNodeDirectory(inPATH path: String) -> Bool {
        findExecutable("node", inPATH: path) != nil
    }

    // MARK: - Lookup helpers

    static func findExecutable(_ name: String, inPATH path: String) -> String? {
        for dir in splitPATH(path) {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func hasExecutable(_ name: String, in directory: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: (directory as NSString).appendingPathComponent(name))
    }

    /// `npm prefix -g` + `/bin`, only consulted when the login shell is unavailable.
    static func npmGlobalBin(env: [String: String]) -> String? {
        var search = knownBinDirectories
        if let current = env["PATH"] { search.append(contentsOf: splitPATH(current)) }
        search.append(contentsOf: splitPATH(systemDefaultPath))
        let path = mergePaths(search)
        guard let npm = findExecutable("npm", inPATH: path) else { return nil }
        guard let output = runProcess(npm, ["prefix", "-g"], timeout: 3) else { return nil }
        let prefix = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return nil }
        return (prefix as NSString).appendingPathComponent("bin")
    }

    // MARK: - Process helpers

    /// Runs a short-lived process with a timeout; returns stdout ("" when none),
    /// or nil when it could not be launched.
    static func runProcess(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    /// POSIX glob helper (used for `/opt/homebrew/opt/node*/bin` etc.).
    private static func glob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(pattern, 0, nil, &result) == 0 else { return [] }
        var out: [String] = []
        for index in 0..<Int(result.gl_pathc) {
            if let pointer = result.gl_pathv[index] {
                out.append(String(cString: pointer))
            }
        }
        return out
    }
}
