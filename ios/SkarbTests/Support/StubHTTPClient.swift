import Foundation
@testable import Skarb

/// An `HTTPClient` that answers from a table and remembers what it was asked.
///
/// Tests hand it to the real services, so a view model test exercises the request a service
/// actually builds — path, query and JSON body — instead of a fake standing in for the service.
final class StubHTTPClient: HTTPClient {
    struct Call {
        let method: HTTPMethod
        let path: String
        let query: [URLQueryItem]
        /// The body as the server would read it, or nil when there was none.
        let body: [String: Any]?

        var key: String { "\(method.rawValue) \(path)" }

        func query(_ name: String) -> [String] {
            query.filter { $0.name == name }.compactMap(\.value)
        }
    }

    struct Unanswered: Error, CustomStringConvertible {
        let key: String
        var description: String { "No stubbed response for \(key)" }
    }

    private(set) var calls: [Call] = []
    private var responses: [String: Any] = [:]
    private var failures: [String: Error] = [:]

    /// Answers `METHOD path` with `value` from now on.
    func stub(_ method: HTTPMethod, _ path: String, with value: Any) {
        responses["\(method.rawValue) \(path)"] = value
    }

    func fail(_ method: HTTPMethod, _ path: String, with error: Error) {
        failures["\(method.rawValue) \(path)"] = error
    }

    func calls(to method: HTTPMethod, _ path: String) -> [Call] {
        calls.filter { $0.method == method && $0.path == path }
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        var body: [String: Any]?
        if let payload = request.body {
            let data = try JSONCoding.encoder().encode(payload)
            body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let call = Call(method: request.method, path: request.path, query: request.query, body: body)
        calls.append(call)

        if let error = failures[call.key] { throw error }
        if let nothing = NoContent() as? Response { return nothing }
        guard let value = responses[call.key] as? Response else { throw Unanswered(key: call.key) }
        return value
    }
}
