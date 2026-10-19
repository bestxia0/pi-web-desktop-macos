import Foundation
import Darwin

/// `--self-test` assertions for run-record parsing and stale-record handling.
/// Exits non-zero if any check fails. This is the executable test for the
/// detection contract, including the real stale 77414.json scenario.
enum SelfTest {
    private static var failures = 0
    private static var checks = 0

    static func run() -> Int32 {
        Logger.shared.mirrorToStderr = true
        print("Running Pi Web launcher self-test...\n")

        testAgentDirExpansion()
        testRecordDecoding()
        testStaleRecordWithAnsweringURL()
        testLiveLauncher()
        testRoleMismatch()
        testOrphanedNext()
        testURLNotAnswering()
        testOwnPidNeverOurs()
        testTwoRecordsOneStale()
        testReadOnlyDoesNotDelete()
        testPortProbe()
        testLoginProbeParsing()
        testMergePathsDedupes()
        testGuiPathFallbackResolvesHomebrew()
        testChildPathContainsNodeDirectory()
        testStopCommandArguments()
        testStopMenuItems()
        testStopAttachedPreference()
        testHotKeyPreference()
        testHotKeyClassifier()
        testHotKeyDebounce()
        testWindowToggleDecision()
        testVersionComposition()

        print("\n\(checks) checks, \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Helpers

    private static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if condition {
            print("  PASS  \(message)")
        } else {
            failures += 1
            print("  FAIL  \(message)")
        }
    }

    private static func makeRecord(
        pid: Int, nextPid: Int, port: Int = 30141,
        url: String = "http://127.0.0.1:30141"
    ) -> RunRecord {
        RunRecord(
            pid: pid, nextPid: nextPid, port: port,
            hostname: "127.0.0.1", url: url, version: "0.12.1",
            startedAt: "2026-10-18T10:18:05.307Z"
        )
    }

    private static func stub(
        alive: @escaping (Int) -> Bool,
        args: @escaping (Int) -> String?,
        answering: @escaping (String) -> Bool
    ) -> RunRecordStore {
        var store = RunRecordStore(directory: "/nonexistent")
        store.isAlive = alive
        store.readArgs = args
        store.isAnswering = answering
        return store
    }

    // MARK: - Tests

    private static func testAgentDirExpansion() {
        print("agentDir expansion")
        check(AppConfig.expandAgentDir("~", home: "/Users/x") == "/Users/x", "~ expands to home")
        check(AppConfig.expandAgentDir("~/a/b", home: "/Users/x") == "/Users/x/a/b", "~/a/b expands")
        check(AppConfig.expandAgentDir("file:///tmp/agent", home: "/Users/x") == "/tmp/agent", "file:// expands to path")
        check(AppConfig.expandAgentDir("/abs/dir", home: "/Users/x") == "/abs/dir", "absolute path unchanged")
    }

    private static func testRecordDecoding() {
        print("record decoding")
        let json = #"{"pid":59656,"nextPid":59657,"port":30141,"hostname":"127.0.0.1","url":"http://127.0.0.1:30141","version":"0.12.1","startedAt":"2026-10-18T10:18:05.307Z"}"#
        let record = try? JSONDecoder().decode(RunRecord.self, from: Data(json.utf8))
        check(record?.pid == 59656, "parses pid")
        check(record?.nextPid == 59657, "parses nextPid")
        check(record?.url == "http://127.0.0.1:30141", "parses url")
    }

    private static func testStaleRecordWithAnsweringURL() {
        print("stale record whose URL still answers (the 77414 case)")
        let store = stub(alive: { _ in false }, args: { _ in "" }, answering: { _ in true })
        let record = makeRecord(pid: 77414, nextPid: 77415)
        check(store.classify(record, sourcePath: "77414.json") == nil,
              "dead pid is stale even though the URL answers")
    }

    private static func testLiveLauncher() {
        print("live launcher")
        let store = stub(
            alive: { $0 == 59656 },
            args: { $0 == 59656 ? "node /opt/homebrew/bin/pi-web" : "" },
            answering: { _ in true }
        )
        let record = makeRecord(pid: 59656, nextPid: 59657)
        let instance = store.classify(record, sourcePath: "59656.json")
        check(instance?.stopPid == 59656, "stopPid is the launcher")
        check(instance?.orphaned == false, "not orphaned")
    }

    private static func testRoleMismatch() {
        print("pid alive but not our process")
        let store = stub(alive: { _ in true }, args: { _ in "python server.py" }, answering: { _ in true })
        let record = makeRecord(pid: 4321, nextPid: 4322)
        check(store.classify(record, sourcePath: "4321.json") == nil, "unrelated process is stale")
    }

    private static func testOrphanedNext() {
        print("orphaned Next.js server")
        let store = stub(
            alive: { $0 == 778 },
            args: { $0 == 778 ? "next-server (v16.3.8)" : "" },
            answering: { _ in true }
        )
        let record = makeRecord(pid: 777, nextPid: 778)
        let instance = store.classify(record, sourcePath: "777.json")
        check(instance?.stopPid == 778, "stopPid falls back to nextPid")
        check(instance?.orphaned == true, "marked orphaned")
    }

    private static func testURLNotAnswering() {
        print("process alive but URL silent")
        let store = stub(
            alive: { $0 == 59656 },
            args: { $0 == 59656 ? "node /opt/homebrew/bin/pi-web" : "" },
            answering: { _ in false }
        )
        let record = makeRecord(pid: 59656, nextPid: 59657)
        check(store.classify(record, sourcePath: "59656.json") == nil, "silent URL is skipped")
    }

    private static func testOwnPidNeverOurs() {
        print("our own pid is never pi-web")
        let store = stub(alive: { _ in true }, args: { _ in "PiWeb pi-web-desktop" }, answering: { _ in true })
        let record = makeRecord(pid: Int(getpid()), nextPid: Int(getpid()))
        check(store.classify(record, sourcePath: "self.json") == nil,
              "our own process path containing 'pi-web' does not match")
    }

    private static func testTwoRecordsOneStale() {
        print("full scenario: two records, one stale, same URL")
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("piweb-selftest-\(getpid())")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let liveJSON = #"{"pid":59656,"nextPid":59657,"port":30141,"hostname":"127.0.0.1","url":"http://127.0.0.1:30141","version":"0.12.1","startedAt":"2026-10-18T10:18:05.307Z"}"#
        let staleJSON = #"{"pid":77414,"nextPid":77415,"port":30141,"hostname":"127.0.0.1","url":"http://127.0.0.1:30141","version":"0.12.1","startedAt":"2026-10-16T13:16:32.765Z"}"#
        try? liveJSON.write(toFile: (dir as NSString).appendingPathComponent("59656.json"), atomically: true, encoding: .utf8)
        try? staleJSON.write(toFile: (dir as NSString).appendingPathComponent("77414.json"), atomically: true, encoding: .utf8)

        var store = RunRecordStore(directory: dir)
        store.isAlive = { $0 == 59656 || $0 == 59657 }
        store.readArgs = { pid in
            switch pid {
            case 59656: return "node /opt/homebrew/bin/pi-web"
            case 59657: return "next-server (v16.3.8)"
            default: return ""
            }
        }
        store.isAnswering = { _ in true } // both point at the same answering URL

        let live = store.detectLiveInstances()
        check(live.count == 1, "exactly one live instance despite two records")
        check(live.first?.stopPid == 59656, "the live one is 59656")
        check(store.loadRecords().count == 2, "both record files were read")
    }

    private static func testReadOnlyDoesNotDelete() {
        print("read-only guarantee: detection never deletes records")
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("piweb-selftest-ro-\(getpid())")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let stalePath = (dir as NSString).appendingPathComponent("77414.json")
        let staleJSON = #"{"pid":77414,"nextPid":77415,"port":30141,"hostname":"127.0.0.1","url":"http://127.0.0.1:30141","version":"0.12.1","startedAt":"2026-10-16T13:16:32.765Z"}"#
        try? staleJSON.write(toFile: stalePath, atomically: true, encoding: .utf8)

        var store = RunRecordStore(directory: dir)
        store.isAlive = { _ in false }
        store.readArgs = { _ in "" }
        store.isAnswering = { _ in true }
        _ = store.detectLiveInstances()
        check(FileManager.default.fileExists(atPath: stalePath), "stale record file still exists after detection")
    }

    private static func testPortProbe() {
        print("port probing")
        let freePort = PortPlanner.ephemeralPort()
        check(freePort != nil, "kernel assigns an ephemeral port")

        // Occupy a real port, then confirm we report it as busy.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd >= 0 {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            _ = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            _ = listen(fd, 1)
            var out = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &out) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(fd, $0, &len)
                }
            }
            let occupied = Int(UInt16(bigEndian: out.sin_port))
            check(!PortPlanner.isFree(port: occupied), "a listening port reports not-free")
            if let fallback = PortPlanner.findFreePort(startingAt: AppConfig.fallbackPortBase) {
                check(fallback >= AppConfig.fallbackPortBase && fallback != occupied,
                      "findFreePort returns a usable fallback")
            } else {
                check(false, "findFreePort returned nil")
            }
            close(fd)
        } else {
            check(false, "could not open probe socket")
        }
    }

    private static func testLoginProbeParsing() {
        print("login shell probe parsing")
        let noisy = "some rc noise\nPIWEB_PATH=/opt/homebrew/bin/pi-web\nLOGIN_PATH=/opt/homebrew/bin:/usr/bin:/bin\n"
        let probe = EnvironmentResolver.parseProbeOutput(noisy)
        check(probe.piWeb == "/opt/homebrew/bin/pi-web", "parses command -v pi-web output")
        check(probe.path == "/opt/homebrew/bin:/usr/bin:/bin", "parses login PATH")

        let empty = EnvironmentResolver.parseProbeOutput("PIWEB_PATH=\nLOGIN_PATH=/usr/bin\n")
        check(empty.piWeb == nil, "empty command -v result becomes nil")
        check(empty.path == "/usr/bin", "still parses PATH when pi-web is absent")
    }

    private static func testMergePathsDedupes() {
        print("PATH merge")
        check(EnvironmentResolver.mergePaths(["/a", "/b", "/a", "", " /b "]) == "/a:/b",
              "mergePaths de-dupes, trims and drops empties")
    }

    /// What is under test is the search-path logic, not the presence of a local
    /// install. A clean CI runner has no `pi-web`, so each assertion is scoped
    /// to the branch the machine can actually exercise; the deterministic parts
    /// (known bin directories, never using the login shell when probing is off)
    /// are asserted unconditionally.
    private static func testGuiPathFallbackResolvesHomebrew() {
        print("GUI PATH (only /usr/bin:/bin:/usr/sbin:/sbin) still resolves pi-web")
        let guiEnv = ["PATH": EnvironmentResolver.systemDefaultPath]
        let resolved = PiWebResolver.resolveEnvironment(
            env: guiEnv, userPath: nil, forceProbe: true, useCache: false, probeLoginShell: false
        )
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/pi-web") {
            check(resolved.spec.executable == "/opt/homebrew/bin/pi-web",
                  "resolves /opt/homebrew/bin/pi-web from system-default PATH")
            check(!resolved.spec.displayCommand.contains("npx"),
                  "does not fall back to npx when a local install exists")
            check(resolved.source == "search-path", "found via known-directory search")
        } else {
            check(resolved.source != "login-shell",
                  "no local pi-web: does not use the login shell when probing is disabled")
            check(!resolved.spec.executable.isEmpty,
                  "no local pi-web: still yields a launch executable")
        }
        check(resolved.childPATH.contains("/opt/homebrew/bin"),
              "child PATH always includes the known bin directories")
    }

    /// PATH assembly is deterministic; whether `node` is installed is not.
    private static func testChildPathContainsNodeDirectory() {
        print("child PATH contains node when node is installed")
        let guiEnv = ["PATH": EnvironmentResolver.systemDefaultPath]
        let path = EnvironmentResolver.effectivePATH(loginPATH: nil, env: guiEnv)
        check(path.contains("/opt/homebrew/bin"), "child PATH includes /opt/homebrew/bin")
        let node = EnvironmentResolver.findExecutable("node", inPATH: path)
        check(EnvironmentResolver.containsNodeDirectory(inPATH: path) == (node != nil),
              "containsNodeDirectory agrees with findExecutable")
        if node != nil {
            check(EnvironmentResolver.containsNodeDirectory(inPATH: path),
                  "child PATH contains a node directory")
        }
    }

    private static func testStopCommandArguments() {
        print("pi-web stop command construction")
        let direct = ResolvedEnvironment(
            spec: LaunchSpec(executable: "/opt/homebrew/bin/pi-web", arguments: []),
            childPATH: "/opt/homebrew/bin:/usr/bin", source: "login-shell",
            piWebPath: "/opt/homebrew/bin/pi-web", loginShellPATH: nil
        )
        let directCmd = PiWebCommands.stopCommand(direct, port: 30141)
        check(directCmd.executable == "/opt/homebrew/bin/pi-web", "stop uses the resolved pi-web executable")
        check(directCmd.arguments == ["stop", "--port", "30141"], "stop appends stop --port N")

        let npx = ResolvedEnvironment(
            spec: LaunchSpec(executable: "/opt/homebrew/bin/npx", arguments: ["-y", "@agegr/pi-web@latest"]),
            childPATH: "/opt/homebrew/bin", source: "npx-search",
            piWebPath: nil, loginShellPATH: nil
        )
        let npxCmd = PiWebCommands.stopCommand(npx, port: 30199)
        check(npxCmd.arguments == ["-y", "@agegr/pi-web@latest", "stop", "--port", "30199"],
              "stop appends after npx leading arguments")
    }

    private static func testStopMenuItems() {
        print("multi-instance stop menu data")
        let a = DetectedInstance(
            record: makeRecord(pid: 100, nextPid: 101, port: 30141, url: "http://127.0.0.1:30141"),
            stopPid: 100, orphaned: false, sourcePath: "100.json"
        )
        let b = DetectedInstance(
            record: makeRecord(pid: 200, nextPid: 201, port: 30199, url: "http://127.0.0.1:30199"),
            stopPid: 200, orphaned: false, sourcePath: "200.json"
        )
        let items = StopMenu.items(for: [a, b], ownedPid: 100)
        check(items.count == 2, "one entry per live instance")
        check(items[0].owned && !items[1].owned, "ownership is flagged per instance")
        check(items[0].title.contains("30141") && items[0].title.contains("100"), "entry shows url and pid")
        check(items[1].title.contains("30199"), "second entry shows its own url")
        check(items[1].port == 30199 && items[1].pid == 200, "entry carries port and pid for the stop call")
        check(StopMenu.items(for: [], ownedPid: nil).isEmpty, "no entries when nothing is running")
    }

    private static func testStopAttachedPreference() {
        print("stop-attached-on-quit preference")
        guard let suite = UserDefaults(suiteName: "com.piweb.desktop.selftest") else {
            check(false, "could not create isolated UserDefaults suite")
            return
        }
        suite.removeObject(forKey: Preferences.stopAttachedOnQuitKey)
        check(Preferences.stopAttachedOnQuit(from: suite) == true, "defaults to ON when the key is unset")
        Preferences.setStopAttachedOnQuit(false, in: suite)
        check(Preferences.stopAttachedOnQuit(from: suite) == false, "persists OFF")
        Preferences.setStopAttachedOnQuit(true, in: suite)
        check(Preferences.stopAttachedOnQuit(from: suite) == true, "persists ON")
        suite.removeObject(forKey: Preferences.stopAttachedOnQuitKey)
    }

    private static func testHotKeyPreference() {
        print("right-Option hotkey preference")
        guard let suite = UserDefaults(suiteName: "com.piweb.desktop.selftest.hotkey") else {
            check(false, "could not create isolated UserDefaults suite")
            return
        }
        suite.removeObject(forKey: Preferences.hotKeyEnabledKey)
        check(Preferences.hotKeyEnabled(from: suite) == true, "defaults to ON when the key is unset")
        Preferences.setHotKeyEnabled(false, in: suite)
        check(Preferences.hotKeyEnabled(from: suite) == false, "persists OFF")
        Preferences.setHotKeyEnabled(true, in: suite)
        check(Preferences.hotKeyEnabled(from: suite) == true, "persists ON")
        suite.removeObject(forKey: Preferences.hotKeyEnabledKey)
    }

    private static func testHotKeyClassifier() {
        print("hotkey classifier (right Option only)")
        check(HotKeyMonitor.classify(keyCode: 61, flags: [.maskAlternate]) == .pressed,
              "right Option down -> pressed")
        check(HotKeyMonitor.classify(keyCode: 61, flags: []) == .released,
              "right Option up -> released")
        check(HotKeyMonitor.classify(keyCode: 58, flags: [.maskAlternate]) == .ignored,
              "left Option down -> ignored")
        check(HotKeyMonitor.classify(keyCode: 58, flags: []) == .ignored,
              "left Option up -> ignored")
        check(HotKeyMonitor.classify(keyCode: 0, flags: [.maskAlternate]) == .ignored,
              "unrelated key -> ignored")
        check(HotKeyMonitor.classify(keyCode: 61, flags: [.maskAlternate, .maskCommand]) == .ignored,
              "right Option with another modifier -> ignored")
    }

    private static func testHotKeyDebounce() {
        print("hotkey debounce state machine")
        check(HotKeyMonitor.decide(keyCode: 61, flags: [.maskAlternate], isDown: false)
                == HotKeyMonitor.Decision(fire: true, isDown: true),
              "right Option down fires once")
        check(HotKeyMonitor.decide(keyCode: 61, flags: [.maskAlternate], isDown: true)
                == HotKeyMonitor.Decision(fire: false, isDown: true),
              "right Option held does not double fire")
        check(HotKeyMonitor.decide(keyCode: 61, flags: [], isDown: true)
                == HotKeyMonitor.Decision(fire: false, isDown: false),
              "right Option release clears the latch")
        check(HotKeyMonitor.decide(keyCode: 58, flags: [], isDown: true)
                == HotKeyMonitor.Decision(fire: false, isDown: false),
              "left Option release clears the overlap latch")
        check(HotKeyMonitor.decide(keyCode: 58, flags: [.maskAlternate], isDown: true)
                == HotKeyMonitor.Decision(fire: false, isDown: true),
              "left Option keeps the latch")
        check(HotKeyMonitor.decide(keyCode: 61, flags: [.maskAlternate, .maskCommand], isDown: false)
                == HotKeyMonitor.Decision(fire: false, isDown: false),
              "right Option chord does not fire")
    }

    private static func testWindowToggleDecision() {
        print("native window toggle decision")
        check(AppWindowController.toggleAction(isVisible: true, isKey: true) == .hide,
              "visible + key -> hide")
        check(AppWindowController.toggleAction(isVisible: true, isKey: false) == .show,
              "visible but not key -> show")
        check(AppWindowController.toggleAction(isVisible: false, isKey: false) == .show,
              "hidden -> show")
        check(AppWindowController.toggleAction(isVisible: false, isKey: true) == .show,
              "hidden (key stale) -> show")
    }

    private static func testVersionComposition() {
        print("version string shown at the bottom of the menu")
        check(
            VersionInfo.compose(semantic: "0.5.0", date: "20261019") == "0.5.0-20261019",
            "composes semantic version and build date"
        )
        check(
            VersionInfo.compose(semantic: " 0.5.0 ", date: " 20261019 ") == "0.5.0-20261019",
            "trims whitespace before composing"
        )
        check(
            VersionInfo.display(raw: "0.5.0-20261019") == "V0.5.0-20261019",
            "menu shows the version behind a V"
        )
        check(
            VersionInfo.compose(semantic: "0.5.0", date: "") == "0.5.0-dev",
            "an empty build date becomes a development build"
        )
        check(
            VersionInfo.compose(semantic: "", date: "") == VersionInfo.fallback,
            "an empty version falls back instead of showing blank"
        )
        check(
            VersionInfo.display(raw: "   ") == "V\(VersionInfo.fallback)",
            "a blank plist value still shows a usable string"
        )
        check(
            VersionInfo.compose(semantic: "", date: "20261019") == "20261019",
            "a missing semantic version still shows the date"
        )
        check(!VersionInfo.rawVersion.isEmpty, "the running build reports a non-empty version")
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: VersionInfo.plistKey) as? String {
            check(
                VersionInfo.displayVersion == "V\(fromPlist)",
                "menu string matches the Info.plist version key"
            )
        } else {
            check(
                VersionInfo.displayVersion.hasPrefix("V"),
                "outside a built bundle the version still starts with V"
            )
        }
    }
}
