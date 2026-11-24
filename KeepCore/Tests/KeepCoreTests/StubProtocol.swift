import Foundation
import XCTest
@testable import KeepCore

/// Answers requests from a table instead of the network, and records what was asked.
final class StubProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let query: String?
        let headers: [String: String]
        let body: Data
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
    }

    struct Answer {
        var status = 200
        var body = Data()
        var error: URLError?
        static func json(_ status: Int = 200, _ text: String) -> Answer { Answer(status: status, body: Data(text.utf8)) }
        static func empty(_ status: Int = 204) -> Answer { Answer(status: status) }
        static let offline = Answer(error: URLError(.notConnectedToInternet))
    }

    static var handler: (Recorded) -> Answer = { _ in .empty(500) }
    static var requests: [Recorded] = []
    static let lock = NSLock()

    static func reset(_ handler: @escaping (Recorded) -> Answer) {
        lock.lock()
        defer { lock.unlock() }
        requests = []
        self.handler = handler
    }

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    static func client(credential: String? = "cred-1", lang: String = "en") -> APIClient {
        APIClient(baseURL: URL(string: "https://core.example")!, credential: credential, lang: lang, session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let url = request.url!
        let recorded = Recorded(method: request.httpMethod ?? "GET", path: url.path, query: url.query,
                                headers: request.allHTTPHeaderFields ?? [:], body: body)
        Self.lock.lock()
        Self.requests.append(recorded)
        let answer = Self.handler(recorded)
        Self.lock.unlock()
        if let error = answer.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepcore-tests-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
