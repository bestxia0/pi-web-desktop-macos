import Foundation
import Darwin

/// Port probing / selection.
///
/// pi-web has no port fallback: if 30141 is taken it exits with
/// "Next.js exited unexpectedly". The shell must therefore pick a free port
/// before spawning.
enum PortPlanner {
    /// True when nothing is listening on 127.0.0.1:<port> (bind succeeds).
    static func isFree(port: Int, host: String = AppConfig.hostname) -> Bool {
        guard port > 0, port <= 65535 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 { return false }
        // A successfully bound socket can still listen; we only used bind as a probe.
        return true
    }

    /// First free port from `startingAt` upward (inclusive).
    static func findFreePort(startingAt: Int, host: String = AppConfig.hostname, attempts: Int = 500) -> Int? {
        guard startingAt > 0 else { return nil }
        let end = min(startingAt + attempts, 65536)
        var port = startingAt
        while port < end {
            if isFree(port: port, host: host) { return port }
            port += 1
        }
        return nil
    }

    /// Kernel-assigned ephemeral port by binding to port 0.
    static func ephemeralPort(host: String = AppConfig.hostname) -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr(host)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &out) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &len)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: out.sin_port))
    }
}
