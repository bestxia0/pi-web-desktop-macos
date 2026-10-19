import AppKit
import CoreGraphics
import ApplicationServices

/// Global hotkey on the **right** Option key.
///
/// A modifier-only hotkey cannot be registered with Carbon's
/// `RegisterEventHotKey`, so this uses a listen-only `CGEvent` tap first and
/// falls back to `NSEvent` global/local monitors when the tap cannot be
/// created (for example before Input Monitoring has been granted). The tap is
/// `.listenOnly` and the callback always returns the untouched event, so right
/// Option keeps working as a normal modifier in every other app.
///
/// `classify(keyCode:flags:)` is pure so `--self-test` can assert the
/// right-vs-left Option contract without a GUI or any permission.
final class HotKeyMonitor {
    /// What a flags-changed event means for this hotkey.
    enum Action: Equatable { case pressed, released, ignored }

    /// Pure debounce decision: whether to fire, and the next latch value.
    struct Decision: Equatable {
        let fire: Bool
        let isDown: Bool
    }

    /// Which mechanism actually took over; surfaced in the menu build log.
    enum Mode: String { case eventTap, monitors, inactive }

    var onToggle: (() -> Void)?
    private(set) var isDown = false
    private(set) var mode: Mode = .inactive
    var enabled = true

    private var started = false
    private var restartedForPermission = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Right Option is keyCode 61 (0x3D); left Option is 58 (0x3A). Only the
    // right one is ever allowed to act.
    static let rightOptionKeyCode: UInt16 = 61

    /// Pure classifier: right Option down/up -> pressed/released; everything
    /// else (including left Option) -> ignored. Right Option only fires when it
    /// is the sole modifier, so right⌥+⌘/⌃/⇧ chords pass through.
    static func classify(keyCode: UInt16, flags: CGEventFlags) -> Action {
        guard keyCode == rightOptionKeyCode else { return .ignored }
        guard flags.contains(.maskAlternate) else { return .released }
        if !flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty { return .ignored }
        return .pressed
    }

    /// Pure debounce state machine so `--self-test` can cover the latch. Any
    /// event with no Option held clears the latch, which unwedges the
    /// left+right Option overlap case.
    static func decide(keyCode: UInt16, flags: CGEventFlags, isDown: Bool) -> Decision {
        if !flags.contains(.maskAlternate) {
            return Decision(fire: false, isDown: false)
        }
        switch classify(keyCode: keyCode, flags: flags) {
        case .pressed:
            return Decision(fire: !isDown, isDown: true)
        case .released:
            return Decision(fire: false, isDown: false)
        case .ignored:
            return Decision(fire: false, isDown: isDown)
        }
    }

    // MARK: - Lifecycle

    /// Starts the hotkey if enabled and not already running. Prefers the event
    /// tap; falls back to NSEvent monitors when the tap cannot be created.
    func start() {
        guard !started, enabled else { return }
        started = true

        let granted = Self.inputMonitoringGranted
        Logger.shared.info("hotkey: starting (inputMonitoringGranted=\(granted))")

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.isDown = false
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    Logger.shared.warn("hotkey: event tap disabled by system; re-enabled")
                }
                return Unmanaged.passUnretained(event)
            }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            monitor.handle(keyCode: keyCode, flags: event.flags)
            return Unmanaged.passUnretained(event)
        }

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            mode = .eventTap
            Logger.shared.info("hotkey: event tap active")
            return
        }

        Logger.shared.warn("hotkey: CGEvent.tapCreate returned nil; falling back to NSEvent monitors")
        installMonitors()
    }

    /// Fallback path: a global monitor (other apps) plus a local one (this app)
    /// for `.flagsChanged`. The local monitor must return the event unchanged.
    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event: event)
            return event
        }
        mode = .monitors
        Logger.shared.info(
            "hotkey: NSEvent monitors active (global=\(globalMonitor != nil) local=\(localMonitor != nil))"
        )
    }

    /// Removes the tap/source and both monitors and returns to `.inactive`.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        isDown = false
        started = false
        mode = .inactive
        Logger.shared.info("hotkey: stopped")
    }

    /// Preference hook: on starts the monitor, off stops it.
    func setEnabled(_ on: Bool) {
        enabled = on
        restartedForPermission = false
        if on {
            start()
        } else {
            stop()
        }
    }

    /// One-shot upgrade from the NSEvent-monitor fallback to the event tap once
    /// Input Monitoring becomes available. Called when the menu is rendered or
    /// the permission helper is used.
    func refreshIfNeeded() {
        guard enabled, mode != .eventTap, Self.inputMonitoringGranted, !restartedForPermission else { return }
        restartedForPermission = true
        Logger.shared.info("hotkey: input monitoring granted; restarting to use the event tap")
        stop()
        start()
    }

    // MARK: - Event handling

    private func handle(event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        handle(keyCode: event.keyCode, flags: flags)
    }

    /// Debounces press/release so one physical press produces exactly one
    /// toggle. The callback is dispatched on the main queue.
    private func handle(keyCode: UInt16, flags: CGEventFlags) {
        let decision = Self.decide(keyCode: keyCode, flags: flags, isDown: isDown)
        isDown = decision.isDown
        guard decision.fire else { return }
        DispatchQueue.main.async { [weak self] in self?.onToggle?() }
    }

    // MARK: - Permissions

    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    static func requestInputMonitoring() { CGRequestListenEventAccess() }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Opens System Settings > Privacy & Security > Input Monitoring.
    static func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
