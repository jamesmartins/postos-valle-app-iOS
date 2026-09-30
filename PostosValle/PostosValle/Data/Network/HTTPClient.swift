import Foundation

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
}

struct Endpoint {
    let urlString: String
    let method: HTTPMethod
    let headers: [String: String]?
    let parameters: [String: Any]?
    /// Timeout por request (padrão 20s — APP.do no device às vezes estoura 30s).
    let timeoutInterval: TimeInterval

    init(
        urlString: String,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        parameters: [String: Any]? = nil,
        timeoutInterval: TimeInterval = 20
    ) {
        self.urlString = urlString
        self.method = method
        self.headers = headers
        self.parameters = parameters
        self.timeoutInterval = timeoutInterval
    }

    func buildRequest() throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "PostosValle-iOS/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")",
            forHTTPHeaderField: "User-Agent"
        )

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let params = parameters {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: params, options: [])
        }

        return request
    }
}

protocol HTTPClientProtocol: Sendable {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func requestRaw(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse)
}

final class HTTPClient: HTTPClientProtocol, @unchecked Sendable {
    static let shared = HTTPClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 45
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = [
                "Accept": "application/json"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, response) = try await requestRaw(endpoint)

        guard 200...299 ~= response.statusCode else {
            throw NetworkError.fromHTTP(statusCode: response.statusCode, data: data)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            // Body 2xx com payload de erro Bunker (`errors[].message`)
            if let bunkerMessage = NetworkError.parseBunkerErrorMessage(from: data) {
                if NetworkError.isAccessKeyOrAuthFailure(bunkerMessage) {
                    throw NetworkError.unauthorized
                }
                throw NetworkError.serverError(bunkerMessage)
            }
            AppLogger.logDecodingFailure(type: T.self, endpoint: endpoint, error: error, data: data)
            throw NetworkError.failedDecoding(error.localizedDescription)
        }
    }

    func requestRaw(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        AppLogger.logRequest(endpoint)
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let urlRequest = try endpoint.buildRequest()
            let (data, response) = try await session.data(for: urlRequest)
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            guard let httpResponse = response as? HTTPURLResponse else {
                let err = NetworkError.requestFailed(-1, "Resposta inválida do servidor.")
                AppLogger.logNetworkFailure(endpoint, error: err, data: data, duration: duration)
                throw err
            }

            if 200...299 ~= httpResponse.statusCode {
                AppLogger.logResponse(endpoint, statusCode: httpResponse.statusCode, data: data, duration: duration)
            } else {
                let err = NetworkError.fromHTTP(statusCode: httpResponse.statusCode, data: data)
                AppLogger.logNetworkFailure(endpoint, statusCode: httpResponse.statusCode, error: err, data: data, duration: duration)
            }

            return (data, httpResponse)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.logNetworkFailure(endpoint, error: error, duration: duration)
            throw error
        }
    }

    /// Retry simples para timeouts / rede instável no device.
    func requestWithRetry<T: Decodable>(_ endpoint: Endpoint, attempts: Int = 3) async throws -> T {
        var lastError: Error?
        for attempt in 1...max(1, attempts) {
            do {
                return try await request(endpoint)
            } catch {
                lastError = error
                guard Self.isTransient(error), attempt < attempts else { throw error }
                let delay = UInt64(300_000_000 * attempt) // 0.3s, 0.6s…
                AppLogger.warning(.network, "Retry \(attempt)/\(attempts) após erro transitório: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? NetworkError.requestFailed(-1, "Falha de rede.")
    }

    private static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                break
            }
        }
        return false
    }
}
