import AppKit
import Foundation
import Darwin

// ===========================================================================
// Pi Web — macOS menu bar launcher shell (entry point)
//
// GUI mode is the default. Headless flags exist so the same binary can verify
// detection, start/stop and port fallback without a display:
//   --self-test, --probe, --test-cycle [--occupy], --test-fallback,
//   --open-url <url>, --resolve, --log-path, --version, --port <n>
// ===========================================================================

let rawArgs = Array(CommandLine.arguments.dropFirst())

func flagValue(_ flag: String) -> String? {
    guard let index = rawArgs.firstIndex(of: flag), index + 1 < rawArgs.count else { return nil }
    return rawArgs[index + 1]
}

func hasFlag(_ flag: String) -> Bool { rawArgs.contains(flag) }

/// Posted by a second launch to ask the running shell to reveal its menu.
let activateNotification = Notification.Name("com.piweb.desktop.activate")

/// Environment used for resolution. `--gui-path` replaces PATH with the
/// system default so the headless test reproduces a LaunchServices launch.
func resolutionEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    if hasFlag("--gui-path") {
        env["PATH"] = EnvironmentResolver.systemDefaultPath
    }
    return env
}

if let portText = flagValue("--port"), let port = Int(portText) {
    AppConfig.preferredPortOverride = port
} else if let envPort = ProcessInfo.processInfo.environment["PI_WEB_DESKTOP_PORT"], let port = Int(envPort) {
    AppConfig.preferredPortOverride = port
}

if hasFlag("--self-test") {
    exit(SelfTest.run())
}

if hasFlag("--log-path") {
    print(AppConfig.logFile)
    exit(0)
}

// Exactly the string the menu's bottom version row shows; also the value a
// future update check would compare against a published release.
if hasFlag("--version") {
    print(VersionInfo.displayVersion)
    exit(0)
}

if hasFlag("--resolve") {
    let usingGuiPath = hasFlag("--gui-path")
    let resolved = PiWebResolver.resolveEnvironment(
        env: resolutionEnvironment(), forceProbe: usingGuiPath, useCache: !usingGuiPath
    )
    print("resolved pi-web: \(resolved.spec.displayCommand)")
    print("source:         \(resolved.source)")
    print("child PATH:     \(resolved.childPATH)")
    print("node:           \(EnvironmentResolver.findExecutable("node", inPATH: resolved.childPATH) ?? "NOT FOUND")")
    print("run dir:        \(AppConfig.runDir())")
    print("browser plan:   \(BrowserOpener.plannedCommand(url: AppConfig.url(port: AppConfig.preferredPort)))")
    exit(0)
}

if hasFlag("--probe") {
    exit(runProbe())
}

if hasFlag("--test-fallback") {
    exit(runTestFallback())
}

if hasFlag("--test-cycle") {
    exit(runTestCycle())
}

if let stopPortText = flagValue("--stop-port"), let stopPort = Int(stopPortText) {
    exit(runStopPort(stopPort))
}

if hasFlag("--test-quit") {
    exit(runTestQuit())
}

if let url = flagValue("--open-url") {
    switch BrowserOpener.openAppMode(url: url) {
    case .appMode(let command):
        print("opened app-mode: \(command)")
        exit(0)
    case .defaultBrowser(let command):
        print("opened default browser: \(command)")
        exit(0)
    case .failed(let reason):
        print("open failed: \(reason)")
        exit(1)
    }
}

runGUI()

// ===========================================================================
// Headless verification modes
// ===========================================================================

/// Prints every run record with its step-2/step-3 classification, then the
/// attach/start decision. Read-only: never deletes records.
func runProbe() -> Int32 {
    Logger.shared.mirrorToStderr = true
    let runDir = AppConfig.runDir()
    print("run dir:  \(runDir)")
    print("log file: \(AppConfig.logFile)")
    print("preferred port: \(AppConfig.preferredPort) (free=\(PortPlanner.isFree(port: AppConfig.preferredPort)))")
    let resolved = PiWebResolver.resolveEnvironment(
        env: resolutionEnvironment(), forceProbe: hasFlag("--gui-path"), useCache: !hasFlag("--gui-path")
    )
    print("resolved pi-web: \(resolved.spec.displayCommand) (source=\(resolved.source))")
    print("child PATH: \(resolved.childPATH)")
    print("node: \(EnvironmentResolver.findExecutable("node", inPATH: resolved.childPATH) ?? "NOT FOUND")")
    print("")

    let store = RunRecordStore(directory: runDir)
    let entries = store.loadRecords()
    print("records found: \(entries.count)")
    for entry in entries {
        let name = (entry.path as NSString).lastPathComponent
        print("- \(name)")
        if let record = entry.record {
            print("    pid=\(record.pid ?? -1) nextPid=\(record.nextPid ?? -1) port=\(record.port ?? -1) v\(record.version ?? "?") started \(record.startedAt ?? "?")")
            print(store.describe(record))
        } else {
            print("    unreadable/invalid JSON")
        }
    }
    print("")

    let live = store.detectLiveInstances()
    print("live instances: \(live.count)")
    for instance in live {
        print("  \(instance.url)  stopPid=\(instance.stopPid)  orphaned=\(instance.orphaned)  v\(instance.version)")
    }
    if let first = live.first {
        print("decision: ATTACH \(first.url) (do not start a second instance)")
    } else {
        print("decision: START (no live instance; would use port \(AppConfig.preferredPort))")
    }
    return 0
}

/// Binds a kernel port and listens on it, returning the fd (or -1).
func occupyPort(_ port: Int) -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var reuse: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0, listen(fd, 1) == 0 else {
        close(fd)
        return -1
    }
    return fd
}

/// Proves the port-fallback selection: occupy the preferred port with a dummy
/// listener, then report which port the planner would pick.
func runTestFallback() -> Int32 {
    Logger.shared.mirrorToStderr = true
    let preferred = AppConfig.preferredPort
    let fd = occupyPort(preferred)
    guard fd >= 0 else {
        print("could not occupy preferred port \(preferred)")
        return 1
    }
    defer { close(fd) }
    print("occupied 127.0.0.1:\(preferred) with a dummy listener")
    print("isFree(\(preferred)) = \(PortPlanner.isFree(port: preferred))")
    let chosen = PortPlanner.findFreePort(startingAt: AppConfig.fallbackPortBase)
    print("fallback chosen: \(chosen.map(String.init) ?? "none")")
    return chosen == nil ? 1 : 0
}

/// Full start -> ready -> stop cycle against a throwaway instance. With
/// `--occupy`, the preferred port is pre-occupied so the fallback path is used
/// too. Never touches the 30141 instance: it only signals the child it spawned.
func runTestCycle() -> Int32 {
    Logger.shared.mirrorToStderr = true
    let preferred = AppConfig.preferredPort
    let occupying = hasFlag("--occupy")
    let usingGuiPath = hasFlag("--gui-path")

    var dummyFd: Int32 = -1
    if occupying {
        dummyFd = occupyPort(preferred)
        guard dummyFd >= 0 else {
            print("could not occupy preferred port \(preferred)")
            return 1
        }
        print("occupied preferred port \(preferred) with a dummy listener")
    }
    defer { if dummyFd >= 0 { close(dummyFd) } }

    let env = resolutionEnvironment()
    if usingGuiPath {
        print("--gui-path: simulating GUI PATH=\(env["PATH"] ?? "")")
    }
    let resolved = PiWebResolver.resolveEnvironment(
        env: env, forceProbe: usingGuiPath, useCache: !usingGuiPath
    )
    let spec = resolved.spec
    print("resolved pi-web: \(spec.displayCommand)")
    print("source:          \(resolved.source)")
    print("child PATH:      \(resolved.childPATH)")
    print("node in PATH:    \(EnvironmentResolver.findExecutable("node", inPATH: resolved.childPATH) ?? "NOT FOUND")")

    let target: Int
    if PortPlanner.isFree(port: preferred) {
        target = preferred
    } else if let fallback = PortPlanner.findFreePort(startingAt: AppConfig.fallbackPortBase) {
        target = fallback
    } else if let ephemeral = PortPlanner.ephemeralPort() {
        target = ephemeral
    } else {
        print("no free port available")
        return 1
    }
    print("preferred=\(preferred) free=\(PortPlanner.isFree(port: preferred)) chosen=\(target)")

    let manager = ProcessManager()
    do {
        let pid = try manager.start(port: target, spec: spec, childPATH: resolved.childPATH)
        print("spawned pid \(pid)")
    } catch {
        print("start failed: \(error.localizedDescription)")
        return 1
    }

    let url = AppConfig.url(port: target)
    let ready = manager.waitForReady(url: url, timeout: 60)
    print("ready=\(ready) url=\(url)")
    if !ready {
        print("failure: \(manager.lastFailure ?? "unknown")")
        print("stop result: \(manager.stop())")
        return 1
    }

    Thread.sleep(forTimeInterval: 1.0)
    let afterStart = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances()
    print("detected after start: \(afterStart.map { "\($0.url)(pid=\($0.stopPid))" })")

    let outcome = manager.stop()
    print("stop result: \(outcome)")

    Thread.sleep(forTimeInterval: 1.0)
    let afterStop = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances()
    print("detected after stop: \(afterStop.map { "\($0.url)(pid=\($0.stopPid))" })")

    return 0
}

/// Evidence helper: stop one instance via the shell's attached path
/// (`pi-web stop --port N`) and print before/after detection.
func runStopPort(_ port: Int) -> Int32 {
    Logger.shared.mirrorToStderr = true
    print("stop-port \(port)")
    let before = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances().filter { $0.port == port }
    print("before: \(before.map { "\($0.url) pid=\($0.stopPid) orphaned=\($0.orphaned)" })")

    let resolved = PiWebResolver.resolveEnvironment(
        env: resolutionEnvironment(), forceProbe: hasFlag("--gui-path"), useCache: !hasFlag("--gui-path")
    )
    let command = PiWebCommands.stopCommand(resolved, port: port)
    print("command: \(command.displayCommand)")
    let result = PiWebCommands.stop(port: port, resolved: resolved, timeout: 30)
    print("exit=\(result.exitCode) timedOut=\(result.timedOut) launched=\(result.launched)")
    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    print("output: \(output.isEmpty ? "<empty>" : output)")

    Thread.sleep(forTimeInterval: 1.0)
    let after = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances().filter { $0.port == port }
    print("after: \(after.map { "\($0.url) pid=\($0.stopPid)" })")
    print("port \(port) free=\(PortPlanner.isFree(port: port))")
    return result.success ? 0 : 1
}

/// Evidence helper for the "stop attached on quit" toggle, scoped to one port
/// so it never touches unrelated instances.
func runTestQuit() -> Int32 {
    Logger.shared.mirrorToStderr = true
    let port = AppConfig.preferredPort
    let stopAttached = !hasFlag("--keep-attached")
    print("test-quit: port=\(port) stopAttached=\(stopAttached)")

    let before = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances().filter { $0.port == port }
    print("before: \(before.map { "\($0.url) pid=\($0.stopPid)" })")

    let controller = StatusController()
    controller.stopForQuit(onlyPorts: [port], stopAttachedOverride: stopAttached)

    Thread.sleep(forTimeInterval: 1.0)
    let after = RunRecordStore(directory: AppConfig.runDir()).detectLiveInstances().filter { $0.port == port }
    print("after: \(after.map { "\($0.url) pid=\($0.stopPid)" })")
    print("port \(port) free=\(PortPlanner.isFree(port: port))")
    return stopAttached ? (after.isEmpty ? 0 : 1) : (after.isEmpty ? 1 : 0)
}

// ===========================================================================
// GUI
// ===========================================================================

/// Single-instance guard. LaunchServices already dedupes bundle launches, but
/// a raw binary run or a race is caught by an exclusive `flock`.
final class SingleInstanceLock {
    private let fd: Int32
    init?(path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return nil
        }
        fd = descriptor
    }
    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

func activateExistingInstance() {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: AppConfig.bundleIdentifier)
    if let existing = apps.first(where: { $0.processIdentifier != getpid() }) {
        existing.activate(options: [.activateAllWindows])
    }
}

func runGUI() {
    // Retained for the process lifetime.
    let instanceLock = SingleInstanceLock(path: AppConfig.lockFile)
    guard instanceLock != nil else {
        Logger.shared.info("another Pi Web launcher holds the lock; posting activate notification and exiting")
        DistributedNotificationCenter.default().postNotificationName(
            activateNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        activateExistingInstance()
        Thread.sleep(forTimeInterval: 0.3)
        exit(0)
    }

    Logger.shared.info("Pi Web launcher starting (bundle=\(AppConfig.bundleIdentifier), runDir=\(AppConfig.runDir()))")
    let resolved = PiWebResolver.resolveEnvironment()
    Logger.shared.info("resolved pi-web: \(resolved.spec.displayCommand)")
    Logger.shared.info("resolved source: \(resolved.source)")
    Logger.shared.info("resolved child PATH: \(resolved.childPATH)")

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusController()
    private var menu: MenuController?
    private var isQuitting = false
    private var activateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuController(controller: controller)
        activateObserver = DistributedNotificationCenter.default().addObserver(
            forName: activateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Logger.shared.info("received activate notification; revealing menu")
            self?.menu?.revealMenu()
        }
        // Double-click = detect, attach or start, and open the window.
        controller.start(openWhenReady: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activateObserver {
            DistributedNotificationCenter.default().removeObserver(activateObserver)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting { return .terminateNow }
        isQuitting = true
        DispatchQueue.global().async {
            self.controller.stopForQuit()
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
