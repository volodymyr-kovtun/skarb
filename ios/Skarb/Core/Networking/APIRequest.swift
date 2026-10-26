import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
}

/// One call to the Skarb API, typed by what it answers with.
///
/// A request is a plain value, so building one is separate from sending it: services describe
/// *what* to ask for and the `HTTPClient` decides *how* — which is what lets a test check the
/// path, query and body a service produces without a server, and swap the transport for a fake.
nonisolated struct APIRequest<Response: Decodable> {
    var method: HTTPMethod
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)?

    static func get(_ path: String, query: [URLQueryItem] = []) -> Self {
        Self(method: .get, path: path, query: query)
    }

    static func post(
        _ path: String, query: [URLQueryItem] = [], body: (any Encodable & Sendable)? = nil
    ) -> Self {
        Self(method: .post, path: path, query: query, body: body)
    }

    static func patch(_ path: String, body: any Encodable & Sendable) -> Self {
        Self(method: .patch, path: path, body: body)
    }

    static func delete(_ path: String) -> Self {
        Self(method: .delete, path: path)
    }
}

/// What an endpoint decodes into when it answers 204, or when nobody reads its answer.
nonisolated struct NoContent: Codable, Sendable {}

/// An empty JSON object, for the handful of POSTs whose handler binds a body it never reads.
nonisolated struct EmptyBody: Encodable, Sendable {}
