import Foundation
import Darwin

/// A pi-web run record, as written by pi-web's `bin/run-records.js`.
/// All fields are optional so a corrupt/partial file decodes to "skip" instead
/// of throwing.
struct RunRecord: Decodable {
    var pid: Int?
    var nextPid: Int?
    var port: Int?
    var hostname: String?
    var url: String?
    var version: String?
    var startedAt: String?
}

/// A run record whose processes are alive AND ours AND whose URL answers.
struct DetectedInstance {
    let record: RunRecord
    let stopPid: Int
    let orphaned: Bool
    let sourcePath: String

    var port: Int { record.port ?? 0 }
    var url: String { record.url ?? AppConfig.url(port: port, host: record.hostname ?? AppConfig.hostname) }
    var version: String { record.version ?? "?" }
}

enum RecordRole {
    case launcher
    case next
}

/// Process inspection primitives matching pi-web's macOS path:
/// `kill(pid, 0)` (EPERM counts as alive) and `ps -ww -p <pid> -o args=`.
enum ProcessInspector {
    static func isAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    /// Returns the command line, "" when the process does not exist, or nil
    /// when we cannot tell at all (used as "assume ours", exactly like pi-web).
    static func readProcessArgs(_ pid: Int) -> String? {
        guard pid > 0 else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(pid), "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads and classifies the run records, following pi-web's exact 3-step
/// order: (1) read all *.json, (2) validate the pid is alive AND is really
/// our process, (3) only then check the URL answers.
///
/// Order matters: the stale record 77414.json points at a URL that still
/// answers because another instance owns 30141, so URL-checking before the
/// process-check would report two live instances.
///
/// Deviation from pi-web: this shell never deletes stale records during
/// detection (read-only). pi-web's own `listRunRecords` prunes them; we choose
/// not to touch the user's records. Stale records are simply ignored.
struct RunRecordStore {
    let directory: String

    var isAlive: (Int) -> Bool = ProcessInspector.isAlive
    var readArgs: (Int) -> String? = ProcessInspector.readProcessArgs
    var isAnswering: (String) -> Bool = { HTTPProbe.isAnswering($0) }

    /// Loads every record, including unreadable ones (record == nil).
    func loadRecords() -> [(path: String, record: RunRecord?)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        var out: [(String, RunRecord?)] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let path = (directory as NSString).appendingPathComponent(name)
            let record = (try? Data(contentsOf: URL(fileURLWithPath: path)))
                .flatMap { try? JSONDecoder().decode(RunRecord.self, from: $0) }
            out.append((path, record))
        }
        return out
    }

    /// True when `pid` is a process of ours for the given role.
    /// A pid equal to our own is never treated as a pi-web process (our own
    /// binary path contains "pi-web", which would otherwise false-match).
    func isOurs(pid: Int, role: RecordRole) -> Bool {
        if pid == Int(getpid()) { return false }
        guard let args = readArgs(pid) else { return true }
        if args.isEmpty { return false }
        switch role {
        case .launcher: return args.contains("pi-web")
        case .next: return args.contains("next")
        }
    }

    /// Steps 2 + 3 for one record. Returns nil when the record is stale.
    func classify(_ record: RunRecord, sourcePath: String) -> DetectedInstance? {
        let launcherLive = (record.pid ?? 0) > 0
            && isAlive(record.pid!) && isOurs(pid: record.pid!, role: .launcher)
        let nextLive = !launcherLive && (record.nextPid ?? 0) > 0
            && isAlive(record.nextPid!) && isOurs(pid: record.nextPid!, role: .next)
        guard launcherLive || nextLive else { return nil }

        // Step 3, last: any HTTP answer counts (including 401), 2s timeout.
        let url = record.url ?? AppConfig.url(port: record.port ?? 0)
        guard !url.isEmpty, isAnswering(url) else { return nil }

        return DetectedInstance(
            record: record,
            stopPid: launcherLive ? record.pid! : record.nextPid!,
            orphaned: !launcherLive,
            sourcePath: sourcePath
        )
    }

    /// Steps 1-3 across the whole directory, sorted by port.
    func detectLiveInstances() -> [DetectedInstance] {
        loadRecords().compactMap { entry in
            guard let record = entry.record else { return nil }
            return classify(record, sourcePath: entry.path)
        }.sorted { $0.port < $1.port }
    }

    /// Human-readable per-record report used by `--probe`.
    func describe(_ record: RunRecord) -> String {
        var lines: [String] = []
        let pid = record.pid ?? -1
        let nextPid = record.nextPid ?? -1
        let alive1 = isAlive(pid)
        let alive2 = isAlive(nextPid)
        lines.append("    launcher pid=\(pid) alive=\(yesNo(alive1)) ours=\(yesNo(alive1 && isOurs(pid: pid, role: .launcher)))")
        lines.append("    next     pid=\(nextPid) alive=\(yesNo(alive2)) ours=\(yesNo(alive2 && isOurs(pid: nextPid, role: .next)))")
        let url = record.url ?? ""
        lines.append("    url=\(url) answering=\(yesNo(!url.isEmpty && isAnswering(url)))")
        if let inst = classify(record, sourcePath: "") {
            lines.append("    => LIVE (stopPid=\(inst.stopPid), orphaned=\(yesNo(inst.orphaned)))")
        } else {
            lines.append("    => STALE (process not ours/dead)")
        }
        return lines.joined(separator: "\n")
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
