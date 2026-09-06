import Foundation

struct HTTPRequest {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    var method: Method
    var path: String
    var query: [String: String] = [:]
    var body: Encodable?
    var extraHeaders: [String: String] = [:]
}

struct EmptyResponse: Decodable {}

struct JSONEnvelope<T: Decodable>: Decodable {
    let data: T
}

protocol HTTPSending {
    func send<T: Decodable>(_ request: HTTPRequest) async throws -> T
    func send(_ request: HTTPRequest) async throws
    func sendRaw(_ request: HTTPRequest) async throws -> Data
}

struct HTTPClient: HTTPSending {
    var baseURL: URL
    var defaultHeaders: [String: String]
    var session: URLSession
    var decoder: JSONDecoder
    var encoder: JSONEncoder
    var logsRequests: Bool
    var timeout: TimeInterval

    init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared,
        decoder: JSONDecoder = HTTPClient.makeDecoder(),
        encoder: JSONEncoder = HTTPClient.makeEncoder(),
        logsRequests: Bool = false,
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.logsRequests = logsRequests
        self.timeout = timeout
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }

    static func appHeaders(accessToken: String? = nil) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-App-Version": AppEnvironment.appVersion,
            "X-Platform": AppEnvironment.platformHeader,
        ]
        if let accessToken, !accessToken.isEmpty {
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        return headers
    }

    func send<T: Decodable>(_ request: HTTPRequest) async throws -> T {
        let data = try await sendData(request)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw AppError.decoding
        }
        return try decode(T.self, from: data)
    }

    func send(_ request: HTTPRequest) async throws {
        _ = try await sendData(request)
    }

    func sendRaw(_ request: HTTPRequest) async throws -> Data {
        try await sendData(request)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        if let envelope = try? decoder.decode(JSONEnvelope<T>.self, from: data) {
            return envelope.data
        }
        throw AppError.decoding
    }

    private func sendData(_ request: HTTPRequest) async throws -> Data {
        let urlRequest = try makeURLRequest(request)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.network
            }
            if logsRequests {
                AppLog.http.info("\(request.method.rawValue, privacy: .public) \(http.url?.absoluteString ?? request.path, privacy: .public) \(http.statusCode, privacy: .public)")
            } else {
                AppLog.http.info("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) \(http.statusCode, privacy: .public)")
            }
            try throwIfNeeded(status: http.statusCode, data: data)
            return data
        } catch let error as AppError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw AppError.cancelled
        } catch {
            throw AppError.network
        }
    }

    private func makeURLRequest(_ request: HTTPRequest) throws -> URLRequest {
        let pathURL = request.path
            .split(separator: "/")
            .reduce(baseURL) { $0.appendingPathComponent(String($1)) }
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            throw AppError.network
        }
        if !request.query.isEmpty {
            components.queryItems = request.query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw AppError.network
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method.rawValue
        var headers = defaultHeaders
        request.extraHeaders.forEach { headers[$0.key] = $0.value }
        headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let body = request.body {
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    private func throwIfNeeded(status: Int, data: Data) throws {
        if status == 426 || APIErrorBody.errorCode(from: data) == "APP_VERSION_NOT_SUPPORTED" {
            let body = APIErrorBody.parse(data)
            throw AppError.versionUnsupported(
                message: body.message ?? L10n.Version.updateRequired,
                storeURL: body.storeURL
            )
        }
        guard (200..<300).contains(status) else {
            let body = APIErrorBody.parse(data)
            throw AppError.http(status: status, message: body.message, errorCode: body.errorCode)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeClosure = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

struct APIErrorBody {
    var message: String?
    var errorCode: String?
    var storeURL: URL?

    static func parse(_ data: Data) -> APIErrorBody {
        guard !data.isEmpty else { return APIErrorBody() }
        if let text = String(data: data, encoding: .utf8),
           text.first != "{", text.first != "[" {
            return APIErrorBody(message: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return APIErrorBody()
        }
        let message = string(object["message"]) ?? string(object["error"]) ?? string(object["upgrade_message"])
        let code = string(object["errorCode"]) ?? string(object["error_code"])
        let store = string(object["storeUrl"]) ?? string(object["store_url"])
        return APIErrorBody(
            message: message,
            errorCode: code,
            storeURL: store.flatMap(URL.init(string:))
        )
    }

    static func errorCode(from data: Data) -> String? {
        parse(data).errorCode
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
