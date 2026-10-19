import Foundation

/// Append-only logger to ~/Library/Logs/PiWeb/pi-web.log.
///
/// The log is the primary diagnostic surface: the menu exposes "Open Log" /
/// "Reveal Log", and failed starts leave their reason in the tail of this file.
final class Logger {
    static let shared = Logger()

    /// When true, also echo to stderr (used by headless CLI/test modes).
    var mirrorToStderr = false

    private let queue = DispatchQueue(label: "com.piweb.logger")
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var path: String { AppConfig.logFile }

    func info(_ message: String) { write("INFO", message) }
    func warn(_ message: String) { write("WARN", message) }
    func error(_ message: String) { write("ERROR", message) }

    func write(_ level: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.sync {
            if mirrorToStderr {
                FileHandle.standardError.write(data)
            }
            let fm = FileManager.default
            try? fm.createDirectory(atPath: AppConfig.logDirectory, withIntermediateDirectories: true)
            if let handle = FileHandle(forWritingAtPath: AppConfig.logFile) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                handle.write(data)
            } else {
                try? data.write(to: URL(fileURLWithPath: AppConfig.logFile))
            }
        }
    }

    /// Last `maxBytes` of the log, for failure diagnosis.
    func tail(maxBytes: Int = 4096) -> String {
        guard let handle = FileHandle(forReadingAtPath: AppConfig.logFile) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        _ = try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
