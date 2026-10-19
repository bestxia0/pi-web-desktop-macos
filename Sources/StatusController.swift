import Foundation

struct StopOutcome {
    let success: Bool
    let message: String
}

/// Orchestrates detection / start / stop and publishes a UI-friendly status.
///
/// All blocking work (HTTP probes, process spawning, waits) runs on a private
/// serial queue; state changes are published on the main queue.
final class StatusController {
    enum Phase: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    private(set) var phase: Phase = .stopped
    private(set) var detail = "尚未探测"
    private(set) var activeURL: String?
    private(set) var activePort: Int?
    private(set) var attached = false
    private(set) var ownedPid: Int?
    private(set) var lastError: String?
    /// Every live instance, sorted by port. Drives the stop menu and the
    /// multi-instance state line.
    private(set) var liveInstances: [DetectedInstance] = []

    var onChange: (() -> Void)?
    /// Installed by the GUI: presents the active URL in the single native
    /// window. When nil, `openWindow()` falls back to `BrowserOpener`.
    var openWindowHandler: ((String) -> Void)?
    var primaryInstance: DetectedInstance? { liveInstances.first }

    let runDir: String
    let preferredPort: Int
    private let processManager = ProcessManager()
    private let work = DispatchQueue(label: "com.piweb.controller")

    init(runDir: String = AppConfig.runDir(), preferredPort: Int = AppConfig.preferredPort) {
        self.runDir = runDir
        self.preferredPort = preferredPort
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            block()
            self.onChange?()
        }
    }

    /// True when this shell spawned the instance (launcher pid or its stopPid).
    func isOwned(_ instance: DetectedInstance) -> Bool {
        guard let ownedPid else { return false }
        return instance.record.pid == ownedPid || instance.stopPid == ownedPid
    }

    // MARK: - Detection

    func refresh() {
        publish { self.detail = "正在探测…" }
        scheduleDetection()
    }

    private func scheduleDetection() {
        work.async { [weak self] in self?.detectNow() }
    }

    /// Runs detection and publishes the result. Callers are already on `work`.
    private func detectNow() {
        let store = RunRecordStore(directory: runDir)
        let live = store.detectLiveInstances()
        let summary = live.map { "\($0.url) pid=\($0.stopPid)\($0.orphaned ? " (orphaned)" : "")" }
        Logger.shared.info("detect: \(live.count) live instance(s) \(summary)")
        publish { self.applyDetection(live) }
    }

    private func applyDetection(_ live: [DetectedInstance]) {
        liveInstances = live
        ownedPid = processManager.ownedPid
        if let primary = live.first {
            attached = !isOwned(primary)
            activeURL = primary.url
            activePort = primary.port
            phase = .running
            if live.count > 1 {
                detail = "运行中（\(live.count) 个实例）"
            } else {
                detail = attached
                    ? "运行中（已附加） \(primary.url) v\(primary.version)"
                    : "运行中（本壳启动） \(primary.url)"
            }
            lastError = nil
            Logger.shared.info("ui state: phase=running attached=\(attached) instances=\(live.count) detail=\(detail)")
        } else if processManager.hasOwnedProcess {
            phase = .running
        } else {
            phase = .stopped
            activeURL = nil
            activePort = nil
            attached = false
            detail = "已停止（未发现运行中的 pi-web）"
        }
    }

    // MARK: - Start

    func start(openWhenReady: Bool = false) {
        guard phase != .starting, phase != .stopping else { return }
        publish { self.phase = .starting; self.detail = "正在选择端口…"; self.lastError = nil }
        work.async { [weak self] in
            guard let self else { return }

            // Re-detect first: never start a second instance.
            let live = RunRecordStore(directory: self.runDir).detectLiveInstances()
            let summary = live.map { "\($0.url) pid=\($0.stopPid)" }
            Logger.shared.info("start detect: \(live.count) live instance(s) \(summary)")
            if let existing = live.first {
                Logger.shared.info("start: live instance already present, attaching \(existing.url)")
                self.publish {
                    self.applyDetection(live)
                    if openWhenReady { _ = self.openWindow() }
                }
                return
            }

            let resolved = PiWebResolver.resolveEnvironment()
            let spec = resolved.spec
            Logger.shared.info(
                "start resolve: exe=\(spec.executable) source=\(resolved.source) "
                + "PATH=\(resolved.childPATH)"
            )
            let targetPort: Int
            if PortPlanner.isFree(port: self.preferredPort) {
                targetPort = self.preferredPort
            } else if let free = PortPlanner.findFreePort(startingAt: AppConfig.fallbackPortBase) {
                Logger.shared.warn("port \(self.preferredPort) busy; falling back to \(free)")
                targetPort = free
            } else if let ephemeral = PortPlanner.ephemeralPort() {
                Logger.shared.warn("port \(self.preferredPort) busy; using ephemeral \(ephemeral)")
                targetPort = ephemeral
            } else {
                self.publish {
                    self.phase = .failed
                    self.lastError = "找不到可用端口"
                    self.detail = "启动失败：找不到可用端口"
                }
                return
            }

            let url = AppConfig.url(port: targetPort)
            self.publish { self.detail = "启动中：\(spec.executable) --port \(targetPort)"; self.activePort = targetPort }

            do {
                let pid = try self.processManager.start(port: targetPort, spec: spec, childPATH: resolved.childPATH)
                self.publish { self.ownedPid = pid; self.attached = false; self.detail = "启动中 pid \(pid) @ \(url)…" }
                if self.processManager.waitForReady(url: url, timeout: 60) {
                    Logger.shared.info("start: ready at \(url)")
                    self.publish {
                        self.phase = .running
                        self.activeURL = url
                        self.activePort = targetPort
                        self.ownedPid = self.processManager.ownedPid
                        self.attached = false
                        self.detail = "运行中（本壳启动） \(url)"
                        self.lastError = nil
                        if openWhenReady { _ = self.openWindow() }
                    }
                    // The run record is written around the same time as Ready;
                    // pick it up on the next work item.
                    self.scheduleDetection()
                } else {
                    let reason = self.processManager.lastFailure ?? "未知错误"
                    Logger.shared.error("start failed: \(reason)")
                    let outcome = self.processManager.stop()
                    self.publish {
                        self.phase = .failed
                        self.lastError = reason
                        self.detail = "启动失败（\(outcome)）"
                    }
                }
            } catch {
                let reason = error.localizedDescription
                Logger.shared.error("start failed: \(reason)")
                self.publish {
                    self.phase = .failed
                    self.lastError = reason
                    self.detail = "启动失败：\(reason)"
                }
            }
        }
    }

    // MARK: - Stop

    /// Stops the primary live instance (single-instance menu item).
    func stop() {
        guard let target = primaryInstance else {
            Logger.shared.warn("stop ignored: no live instance")
            publish { self.detail = "没有可停止的实例" }
            return
        }
        stopInstance(target)
    }

    /// Stops one instance and always re-detects afterwards.
    /// owned -> SIGINT escalation; attached -> `pi-web stop --port N`.
    func stopInstance(_ instance: DetectedInstance) {
        guard phase != .stopping else { return }
        publish { self.phase = .stopping; self.detail = "正在停止 \(instance.url)…"; self.lastError = nil }
        work.async { [weak self] in
            guard let self else { return }
            let outcome: StopOutcome
            if self.isOwned(instance) {
                outcome = self.stopOwnedProcess()
            } else {
                outcome = self.stopAttachedInstance(instance)
            }
            Logger.shared.info("stop \(instance.url): success=\(outcome.success) \(outcome.message)")
            // Re-detect so the menu reflects reality; this is the "sync" core.
            self.detectNow()
            if !outcome.success {
                self.publish {
                    self.phase = .failed
                    self.lastError = outcome.message
                    self.detail = "停止失败：\(instance.url)"
                }
            }
        }
    }

    /// owned path: keep the SIGINT -> SIGTERM -> SIGKILL escalation.
    private func stopOwnedProcess() -> StopOutcome {
        let message = processManager.stop()
        let success = !message.contains("did not exit") && !message.contains("no owned process")
        return StopOutcome(success: success, message: message)
    }

    /// attached path: delegate entirely to upstream `pi-web stop --port N`.
    private func stopAttachedInstance(_ instance: DetectedInstance) -> StopOutcome {
        let resolved = PiWebResolver.resolveEnvironment()
        let command = PiWebCommands.stopCommand(resolved, port: instance.port)
        Logger.shared.info("attached stop via \(command.displayCommand)")
        let result = PiWebCommands.stop(port: instance.port, resolved: resolved, timeout: 30)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.success {
            return StopOutcome(success: true, message: "pi-web stop 成功：\(instance.url)")
        }
        let reason: String
        if !result.launched {
            reason = "无法运行 pi-web stop（\(resolved.source)）"
        } else if result.timedOut {
            reason = "pi-web stop 超时"
        } else {
            reason = "pi-web stop 退出码 \(result.exitCode)"
        }
        return StopOutcome(success: false, message: "\(reason)；\(output.isEmpty ? "无输出" : output)")
    }

    // MARK: - Open

    /// Opens the active URL in the native window when the GUI installed a
    /// handler, otherwise through Chrome-family app mode. Returns whether the
    /// open succeeded.
    @discardableResult
    func openWindow() -> Bool {
        guard let url = activeURL else { return false }
        if let handler = openWindowHandler {
            handler(url)
            return true
        }
        switch BrowserOpener.openAppMode(url: url) {
        case .appMode, .defaultBrowser:
            return true
        case .failed:
            return false
        }
    }

    // MARK: - Quit

    /// Stops the owned child, and (when enabled) every attached instance.
    /// `onlyPorts` and `stopAttachedOverride` exist for the headless verification
    /// so it can be scoped to a test port; the GUI uses the defaults.
    func stopForQuit(onlyPorts: Set<Int>? = nil, stopAttachedOverride: Bool? = nil) {
        let live = RunRecordStore(directory: runDir).detectLiveInstances()
        let owned = processManager.ownedPid

        if onlyPorts == nil, processManager.hasOwnedProcess {
            Logger.shared.info("quit: stopping owned process")
            _ = processManager.stop()
        }

        let stopAttached = stopAttachedOverride ?? Preferences.stopAttachedOnQuit
        if !stopAttached {
            Logger.shared.info("quit: 'stop attached on quit' is off; leaving attached instances untouched")
            return
        }

        let resolved = PiWebResolver.resolveEnvironment()
        for instance in live {
            if let onlyPorts, !onlyPorts.contains(instance.port) { continue }
            let isOwned = owned != nil && (instance.record.pid == owned || instance.stopPid == owned)
            if isOwned { continue }
            Logger.shared.info("quit: stopping attached \(instance.url) via pi-web stop")
            let result = PiWebCommands.stop(port: instance.port, resolved: resolved, timeout: 30)
            Logger.shared.info("quit: pi-web stop --port \(instance.port) exit=\(result.exitCode) timedOut=\(result.timedOut)")
        }
    }
}
