import Foundation
import OSLog

/// Sistema centralizado de Logger para monitoramento de serviços, requisições HTTP e operações de dados
enum AppLogger: Sendable {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "br.com.marka.postovalle"

    // Instâncias do OSLog categorizadas
    private static let networkLogger = Logger(subsystem: subsystem, category: "Network")
    private static let repositoryLogger = Logger(subsystem: subsystem, category: "Repository")
    private static let authLogger = Logger(subsystem: subsystem, category: "Auth")
    private static let appLogger = Logger(subsystem: subsystem, category: "App")

    enum Category: Sendable {
        case network
        case repository
        case auth
        case app

        var logger: Logger {
            switch self {
            case .network: return AppLogger.networkLogger
            case .repository: return AppLogger.repositoryLogger
            case .auth: return AppLogger.authLogger
            case .app: return AppLogger.appLogger
            }
        }
    }

    // MARK: - Network Request / Response Logging

    /// Registra o disparo de uma requisição HTTP
    static func logRequest(_ endpoint: Endpoint) {
        var log = """
        \n🚀 [REQUEST] \(endpoint.method.rawValue) \(endpoint.urlString)
        """

        if let headers = endpoint.headers, !headers.isEmpty {
            let maskedHeaders = maskSensitiveHeaders(headers)
            log += "\n  📋 Headers: \(maskedHeaders)"
        }

        if let params = endpoint.parameters, !params.isEmpty {
            if let jsonData = try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                log += "\n  📤 Body:\n\(indent(jsonString, spaces: 4))"
            } else {
                log += "\n  📤 Parameters: \(params)"
            }
        }

        networkLogger.info("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra uma resposta HTTP recebida com sucesso (2xx)
    static func logResponse(
        _ endpoint: Endpoint,
        statusCode: Int,
        data: Data,
        duration: TimeInterval
    ) {
        let durationFormatted = String(format: "%.3fs", duration)
        let sizeFormatted = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)

        var log = """
        \n✅ [RESPONSE SUCCESS] (\(statusCode)) in \(durationFormatted) [\(sizeFormatted)]
          URL: \(endpoint.method.rawValue) \(endpoint.urlString)
        """

        if let pretty = prettyJSON(from: data) {
            log += "\n  📥 Payload:\n\(indent(pretty, spaces: 4))"
        } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            log += "\n  📥 Payload: \(text)"
        }

        networkLogger.info("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra uma falha de rede ou HTTP com status de erro (ex: 4xx, 5xx)
    static func logNetworkFailure(
        _ endpoint: Endpoint,
        statusCode: Int? = nil,
        error: Error,
        data: Data? = nil,
        duration: TimeInterval? = nil
    ) {
        let durationFormatted = duration.map { String(format: " in %.3fs", $0) } ?? ""
        let statusFormatted = statusCode.map { " (\($0))" } ?? ""

        var log = """
        \n❌ [NETWORK FAILURE]\(statusFormatted)\(durationFormatted)
          URL: \(endpoint.method.rawValue) \(endpoint.urlString)
          Erro: \(error.localizedDescription)
        """

        if let data = data {
            if let pretty = prettyJSON(from: data) {
                log += "\n  📥 Payload de Erro:\n\(indent(pretty, spaces: 4))"
            } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                log += "\n  📥 Payload de Erro: \(text)"
            }
        }

        networkLogger.error("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra falhas na decodificação de JSON
    static func logDecodingFailure<T>(
        type: T.Type,
        endpoint: Endpoint,
        error: Error,
        data: Data
    ) {
        var log = """
        \n⚠️ [DECODING ERROR] Falha ao converter JSON para \(String(describing: type))
          URL: \(endpoint.method.rawValue) \(endpoint.urlString)
          Detalhes: \(error)
        """

        if let raw = String(data: data, encoding: .utf8) {
            let truncated = raw.count > 1000 ? String(raw.prefix(1000)) + " ... [truncado]" : raw
            log += "\n  📥 JSON Bruto:\n\(indent(truncated, spaces: 4))"
        }

        networkLogger.error("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    // MARK: - Repositories & Business Logic Logging

    /// Registra uma operação de negócio executada com sucesso
    static func logSuccess(
        _ category: Category,
        operation: String,
        details: String? = nil
    ) {
        var log = "✨ [SUCCESS - \(category)] \(operation)"
        if let details = details, !details.isEmpty {
            log += "\n   ↳ \(details)"
        }

        category.logger.info("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra uma falha de regra de negócio ou erro retornado pelo backend
    static func logFailure(
        _ category: Category,
        operation: String,
        error: Error,
        details: String? = nil
    ) {
        var log = "💥 [FAILURE - \(category)] \(operation) -> \(error.localizedDescription)"
        if let details = details, !details.isEmpty {
            log += "\n   ↳ Detalhes: \(details)"
        }

        category.logger.error("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra mensagem informativa geral
    static func info(_ category: Category, _ message: String) {
        let log = "ℹ️ [INFO - \(category)] \(message)"
        category.logger.info("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    /// Registra aviso de atenção
    static func warning(_ category: Category, _ message: String) {
        let log = "⚠️ [WARNING - \(category)] \(message)"
        category.logger.warning("\(log, privacy: .public)")
        #if DEBUG
        print(log)
        #endif
    }

    // MARK: - Helpers

    private static func prettyJSON(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }

    private static func indent(_ string: String, spaces: Int) -> String {
        let indentation = String(repeating: " ", count: spaces)
        return string.components(separatedBy: "\n").map { indentation + $0 }.joined(separator: "\n")
    }

    private static func maskSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        var masked = headers
        for key in ["authorizationCode", "Authorization", "token", "password"] {
            if let val = masked[key] {
                if val.count > 10 {
                    let prefix = val.prefix(4)
                    let suffix = val.suffix(4)
                    masked[key] = "\(prefix)...\(suffix) (len: \(val.count))"
                } else {
                    masked[key] = "******"
                }
            }
        }
        return masked
    }
}
