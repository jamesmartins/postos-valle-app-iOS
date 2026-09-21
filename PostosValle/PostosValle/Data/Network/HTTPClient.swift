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

    func buildRequest() throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30

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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, response) = try await requestRaw(endpoint)

        guard 200...299 ~= response.statusCode else {
            let errorMsg = String(data: data, encoding: .utf8)
            let error = NetworkError.requestFailed(response.statusCode, errorMsg)
            throw error
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
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
                let err = NetworkError.requestFailed(httpResponse.statusCode, String(data: data, encoding: .utf8))
                AppLogger.logNetworkFailure(endpoint, statusCode: httpResponse.statusCode, error: err, data: data, duration: duration)
            }

            return (data, httpResponse)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.logNetworkFailure(endpoint, error: error, duration: duration)
            throw error
        }
    }
}
