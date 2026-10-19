import Foundation
import Darwin

struct CommandResult {
    let exitCode: Int32
    let output: String
    let timedOut: Bool
    let launched: Bool

    var success: Bool { launched && !timedOut && exitCode == 0 }
}

/// Reuses the upstream `pi-web stop --port <N>` command for instances this
/// shell did not start.
///
/// Upstream (`bin/pi-web-commands.js`) already handles every edge case:
/// orphaned records via `record.stopPid ?? record.pid`, ownership validation
/// through `listRunRecords`/`isRecordProcess`, run-record cleanup with
/// `removeRunRecord`, and `taskkill /T /F` on Windows. We therefore never
/// re-implement the kill logic; we only build and run the command. `--port` is
/// always passed because without it upstream errors out when several instances
/// are running.
enum PiWebCommands {
    /// Builds `pi-web stop --port N` from an already-resolved invocation.
    /// Appending to `spec.arguments` also covers the npx / `/usr/bin/env npx`
    /// fallbacks (`npx -y @agegr/pi-web@latest stop --port N`).
    static func stopCommand(_ resolved: ResolvedEnvironment, port: Int) -> LaunchSpec {
        LaunchSpec(
            executable: resolved.spec.executable,
            arguments: resolved.spec.arguments + ["stop", "--port", String(port)]
        )
    }

    static func stop(port: Int, resolved: ResolvedEnvironment, timeout: TimeInterval = 30) -> CommandResult {
        run(stopCommand(resolved, port: port), path: resolved.childPATH, timeout: timeout)
    }

    /// Runs a short-lived command with a hard timeout, returning exit code and
    /// combined stdout/stderr. The resolved child PATH is injected so node and
    /// the pi-web launcher resolve.
    static func run(_ spec: LaunchSpec, path: String, timeout: TimeInterval) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: spec.executable) else {
            return CommandResult(
                exitCode: -1,
                output: "executable not found: \(spec.executable)",
                timedOut: false, launched: false
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                output: "could not launch \(spec.displayCommand): \(error.localizedDescription)",
                timedOut: false, launched: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            Logger.shared.warn("pi-web stop exceeded \(Int(timeout))s; terminating")
            process.terminate()
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self),
            timedOut: timedOut,
            launched: true
        )
    }
}
