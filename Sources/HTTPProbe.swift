import Foundation

/// Synchronous HTTP liveness probe. Any status code counts as answering
/// (pi-web answers 401 when password-protected), matching pi-web's
/// `isServerAnswering`. Times out after `timeout` seconds.
enum HTTPProbe {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func isAnswering(_ urlString: String, timeout: TimeInterval = 2) -> Bool {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var answered = false
        let task = session.dataTask(with: request) { _, response, _ in
            answered = (response != nil)
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1.0) == .timedOut {
            task.cancel()
            return false
        }
        return answered
    }
}
