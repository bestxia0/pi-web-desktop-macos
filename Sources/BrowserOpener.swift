import Foundation
import AppKit

/// Opens pi-web in a Chrome-family browser's app mode (no address bar).
///
/// The browser executable is invoked directly. `open -a ... --args` cannot be
/// used because macOS drops `--args` when the target app is already running.
/// Detection order: Chrome -> Edge -> Brave -> Arc; otherwise the system's
/// default browser via NSWorkspace.
enum BrowserOpener {
    struct Candidate {
        let name: String
        let executable: String
    }

    static let candidates: [Candidate] = [
        Candidate(name: "Google Chrome", executable: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        Candidate(name: "Microsoft Edge", executable: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
        Candidate(name: "Brave Browser", executable: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
        Candidate(name: "Arc", executable: "/Applications/Arc.app/Contents/MacOS/Arc"),
    ]

    enum Result {
        case appMode(command: String)
        case defaultBrowser(command: String)
        case failed(String)
    }

    static func resolved() -> Candidate? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.executable) }
    }

    static func plannedCommand(url: String) -> String {
        if let candidate = resolved() {
            return "\(candidate.executable) --app=\(url)"
        }
        return "NSWorkspace.shared.open(\(url))"
    }

    @discardableResult
    static func openAppMode(url: String) -> Result {
        if let candidate = resolved() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate.executable)
            process.arguments = ["--app=\(url)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let command = "\(candidate.name): \(candidate.executable) --app=\(url)"
                Logger.shared.info("open app-mode: \(command)")
                return .appMode(command: command)
            } catch {
                Logger.shared.error("app-mode launch failed: \(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
        }

        guard let target = URL(string: url) else { return .failed("invalid url \(url)") }
        NSWorkspace.shared.open(target)
        let command = "default browser: \(url)"
        Logger.shared.info("open: \(command)")
        return .defaultBrowser(command: command)
    }
}
