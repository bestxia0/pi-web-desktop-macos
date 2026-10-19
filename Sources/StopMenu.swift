import Foundation

struct StopMenuItem {
    let title: String
    let port: Int
    let pid: Int
    let owned: Bool
}

/// Pure model for the stop menu, so the multi-instance selection and
/// ownership logic is testable without AppKit.
enum StopMenu {
    static func items(for instances: [DetectedInstance], ownedPid: Int?) -> [StopMenuItem] {
        instances.map { instance in
            let owned = ownedPid != nil
                && (instance.record.pid == ownedPid || instance.stopPid == ownedPid)
            let suffix = owned ? "（本壳）" : ""
            return StopMenuItem(
                title: "\(instance.url)  pid \(instance.stopPid)\(suffix)",
                port: instance.port,
                pid: instance.stopPid,
                owned: owned
            )
        }
    }
}
