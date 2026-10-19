import Foundation
import Darwin

/// How to invoke pi-web: an executable plus leading arguments.
struct LaunchSpec {
    let executable: String
    let arguments: [String]

    var displayCommand: String {
        ([executable] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}

/// Everything needed to launch pi-web in a GUI-like environment: the
/// executable, the PATH to hand the child, and how it was found.
struct ResolvedEnvironment {
    let spec: LaunchSpec
    let childPATH: String
    let source: String
    let piWebPath: String?
    let loginShellPATH: String?
}

/// Resolves the pi-web executable and the child PATH.
///
/// Selection order (unchanged for the first two):
///   1. user-configured path (UserDefaults / PI_WEB_DESKTOP_EXECUTABLE)
///   2. login shell `command -v pi-web`
///   3. scan the known bin directories + login PATH
///   4. `npx -y @agegr/pi-web@latest`
enum PiWebResolver {
    private static var cached: ResolvedEnvironment?
    private static let cacheLock = NSLock()

    private static let loginPathKey = "PiWebLoginShellPATH"
    private static let loginPiWebKey = "PiWebLoginShellPiWeb"

    static func which(_ name: String, env: [String: String]) -> String? {
        let path = env["PATH"] ?? EnvironmentResolver.effectivePATH(loginPATH: nil, env: env)
        return EnvironmentResolver.findExecutable(name, inPATH: path)
    }

    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        userPath: String? = UserDefaults.standard.string(forKey: "PiWebExecutablePath")
    ) -> LaunchSpec {
        resolveEnvironment(env: env, userPath: userPath).spec
    }

    /// Resolves the executable + child PATH and caches the result in-process.
    /// `forceProbe`/`useCache: false` are used by `--gui-path` verification and
    /// the self-test to bypass every cache.
    static func resolveEnvironment(
        env: [String: String] = ProcessInfo.processInfo.environment,
        userPath: String? = UserDefaults.standard.string(forKey: "PiWebExecutablePath"),
        forceProbe: Bool = false,
        useCache: Bool = true,
        probeLoginShell: Bool = true
    ) -> ResolvedEnvironment {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if useCache, !forceProbe, let cached {
            return cached
        }
        let resolved = compute(
            env: env, userPath: userPath,
            probeLoginShell: probeLoginShell, useCrossLaunchCache: useCache
        )
        cached = resolved
        return resolved
    }

    private static func compute(
        env: [String: String],
        userPath: String?,
        probeLoginShell: Bool,
        useCrossLaunchCache: Bool
    ) -> ResolvedEnvironment {
        // 1. Resolve the login shell PATH (and `command -v pi-web`), from cache
        //    when possible so subsequent launches are instant.
        var loginPATH: String?
        var loginPiWeb: String?
        if probeLoginShell {
            let defaults = UserDefaults.standard
            if useCrossLaunchCache,
               let cachedPATH = defaults.string(forKey: loginPathKey),
               let cachedExe = defaults.string(forKey: loginPiWebKey),
               FileManager.default.isExecutableFile(atPath: cachedExe) {
                loginPATH = cachedPATH
                loginPiWeb = cachedExe
                Logger.shared.info("login shell cache hit: pi-web=\(cachedExe)")
            } else if let probe = EnvironmentResolver.loginShellProbe() {
                loginPATH = probe.path
                loginPiWeb = probe.piWeb
                if let path = probe.path { defaults.set(path, forKey: loginPathKey) }
                if let exe = probe.piWeb { defaults.set(exe, forKey: loginPiWebKey) }
                Logger.shared.info("login shell probe: pi-web=\(probe.piWeb ?? "nil") PATH_entries=\(probe.path?.split(separator: ":").count ?? 0)")
            } else {
                Logger.shared.warn("login shell probe failed or timed out; using known directories")
            }
        }

        let childPATH = EnvironmentResolver.effectivePATH(loginPATH: loginPATH, env: env)

        // 2. Explicit paths always win.
        for (candidate, source) in [(userPath, "userPath"), (env["PI_WEB_DESKTOP_EXECUTABLE"], "env-override")] {
            if let path = candidate, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return ResolvedEnvironment(
                    spec: LaunchSpec(executable: path, arguments: []),
                    childPATH: childPATH, source: source, piWebPath: path, loginShellPATH: loginPATH
                )
            }
        }

        // 3. The login shell's own answer.
        if let path = loginPiWeb, FileManager.default.isExecutableFile(atPath: path) {
            return ResolvedEnvironment(
                spec: LaunchSpec(executable: path, arguments: []),
                childPATH: childPATH, source: "login-shell", piWebPath: path, loginShellPATH: loginPATH
            )
        }

        // 4. Scan the known directories + login PATH.
        if let path = EnvironmentResolver.findExecutable("pi-web", inPATH: childPATH) {
            return ResolvedEnvironment(
                spec: LaunchSpec(executable: path, arguments: []),
                childPATH: childPATH, source: "search-path", piWebPath: path, loginShellPATH: loginPATH
            )
        }

        // 5. npx fallback (still gets the corrected PATH so it can find node).
        if let npx = EnvironmentResolver.findExecutable("npx", inPATH: childPATH) {
            return ResolvedEnvironment(
                spec: LaunchSpec(executable: npx, arguments: ["-y", "@agegr/pi-web@latest"]),
                childPATH: childPATH, source: "npx-search", piWebPath: nil, loginShellPATH: loginPATH
            )
        }
        return ResolvedEnvironment(
            spec: LaunchSpec(executable: "/usr/bin/env", arguments: ["npx", "-y", "@agegr/pi-web@latest"]),
            childPATH: childPATH, source: "npx-fallback", piWebPath: nil, loginShellPATH: loginPATH
        )
    }
}

/// Owns the pi-web child process that this shell spawned.
///
/// Only processes spawned here are ever signalled. Instances discovered via
/// run records (attached) are never touched by `stop()`.
final class ProcessManager {
    private(set) var process: Process?
    private(set) var ownedPid: Int?
    private(set) var lastFailure: String?
    private(set) var lastChildPATH: String?
    private(set) var lastExecutable: String?
    private var logHandle: FileHandle?

    var isRunning: Bool {
        guard let process else { return false }
        return process.isRunning
    }

    var hasOwnedProcess: Bool { ownedPid != nil && (process?.isRunning ?? false) }

    // MARK: - Start

    /// Spawns pi-web on `port` with `--no-open`. `childPATH` is injected into
    /// the child environment so `#!/usr/bin/env node` and nested node/npx calls
    /// resolve even when the parent got the system-default PATH.
    @discardableResult
    func start(port: Int, spec: LaunchSpec, childPATH: String? = nil) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments + ["--port", String(port), "--no-open"]
        if let childPATH {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = childPATH
            process.environment = environment
        }

        let handle = try openLogHandle()
        self.logHandle = handle
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice

        self.lastExecutable = spec.executable
        self.lastChildPATH = childPATH

        do {
            try process.run()
        } catch {
            let reason = "could not launch \(spec.executable) "
                + "(PATH=\(childPATH ?? "<inherited>")): \(error.localizedDescription)"
            lastFailure = reason
            Logger.shared.error(reason)
            throw StartFailure.spawnFailed(reason)
        }
        self.process = process
        self.ownedPid = Int(process.processIdentifier)
        Logger.shared.info(
            "spawned pid \(process.processIdentifier): \(spec.displayCommand) --port \(port) --no-open "
            + "(PATH=\(childPATH ?? "<inherited>"))"
        )
        return Int(process.processIdentifier)
    }

    private func openLogHandle() throws -> FileHandle {
        let fm = FileManager.default
        try fm.createDirectory(atPath: AppConfig.logDirectory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: AppConfig.logFile) {
            fm.createFile(atPath: AppConfig.logFile, contents: nil)
        }
        let fd = open(AppConfig.logFile, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else {
            throw StartFailure.spawnFailed("could not open log file \(AppConfig.logFile)")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    // MARK: - Readiness

    /// Polls `url` until any HTTP response arrives. Fails early if the child
    /// exits first, capturing executable + PATH + exit code + log tail.
    func waitForReady(url: String, timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if HTTPProbe.isAnswering(url, timeout: 2) { return true }
            if let process, !process.isRunning {
                lastFailure = failureReport(for: process, phase: "exited before becoming ready")
                Logger.shared.error(lastFailure ?? "pi-web exited before ready")
                return false
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        lastFailure = "timed out after \(Int(timeout))s waiting for \(url) "
            + "(exe=\(lastExecutable ?? "?"), PATH=\(lastChildPATH ?? "<inherited>"))"
        Logger.shared.error(lastFailure ?? "timeout")
        return false
    }

    private func failureReport(for process: Process, phase: String) -> String {
        let status = process.terminationStatus
        let reason: String
        switch process.terminationReason {
        case .exit: reason = "exit code \(status)"
        case .uncaughtSignal: reason = "signal \(status)"
        @unknown default: reason = "status \(status)"
        }
        let tail = String(Logger.shared.tail(maxBytes: 2000).suffix(2000))
        return "pi-web \(phase) (\(reason)); exe=\(lastExecutable ?? "?"), "
            + "PATH=\(lastChildPATH ?? "<inherited>")\n--- log tail ---\n\(tail)"
    }

    // MARK: - Stop (signal escalation)

    /// SIGINT (10s) -> SIGTERM (5s) -> SIGKILL. Next.js holds SSE connections
    /// open, so SIGINT first lets pi-web's instrumentation close the streams
    /// and exit; the later signals are a safety net.
    @discardableResult
    func stop() -> String {
        guard let process, let pid = ownedPid else { return "no owned process to stop" }
        if !process.isRunning {
            reset()
            return "already exited"
        }

        Logger.shared.info("stop pid \(pid): SIGINT")
        kill(pid_t(pid), SIGINT)
        if waitForExit(timeout: 10) {
            reset()
            return "stopped gracefully after SIGINT"
        }

        Logger.shared.warn("stop pid \(pid): SIGTERM")
        kill(pid_t(pid), SIGTERM)
        if waitForExit(timeout: 5) {
            reset()
            return "stopped after SIGTERM escalation"
        }

        Logger.shared.warn("stop pid \(pid): SIGKILL")
        kill(pid_t(pid), SIGKILL)
        let exited = waitForExit(timeout: 3)
        reset()
        return exited ? "killed after SIGKILL" : "did not exit even after SIGKILL"
    }

    private func waitForExit(timeout: TimeInterval) -> Bool {
        guard let process else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !process.isRunning
    }

    private func reset() {
        process = nil
        ownedPid = nil
    }
}

enum StartFailure: Error, LocalizedError {
    case spawnFailed(String)

    var errorDescription: String? {
        switch self {
        case .spawnFailed(let message): return message
        }
    }
}
