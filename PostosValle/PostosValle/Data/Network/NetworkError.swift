import Foundation

enum NetworkError: LocalizedError, Equatable {
    case invalidURL
    case invalidParameters(String)
    case requestFailed(Int, String?)
    case failedDecoding(String)
    case noData
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL da requisição é inválida."
        case .invalidParameters(let message):
            return message
        case .requestFailed(_, let message):
            if let message, Self.isRawJSONPayload(message) {
                return "Não foi possível carregar os dados. Tente novamente."
            }
            return message ?? "Não foi possível concluir a requisição."
        case .failedDecoding:
            return "Não foi possível processar a resposta do servidor."
        case .noData:
            return "Nenhum dado retornado pelo servidor."
        case .unauthorized:
            return "Sessão expirada. Faça login novamente."
        case .serverError(let message):
            if Self.isRawJSONPayload(message) {
                return "Não foi possível carregar os dados. Tente novamente."
            }
            return message
        }
    }

    /// Erros que invalidam a sessão e devem forçar logout (sem mensagem na UI).
    var requiresLogout: Bool {
        switch self {
        case .unauthorized:
            return true
        case .requestFailed(_, let message):
            return Self.isAccessKeyOrAuthFailure(message)
        case .serverError(let message), .invalidParameters(let message):
            return Self.isAccessKeyOrAuthFailure(message)
        default:
            return false
        }
    }

    static func isAccessKeyOrAuthFailure(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let normalized = raw
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .lowercased()

        let signals = [
            "chave de acesso",
            "authorization",
            "nao autorizado",
            "não autorizado",
            "unauthorized",
            "acesso nao autorizado",
            "acesso não autorizado",
            "sessao expirada",
            "sessão expirada",
            "token invalido",
            "token inválido"
        ]
        return signals.contains { normalized.contains($0) }
    }

    static func isRawJSONPayload(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    /// Extrai mensagem amigável de payloads Bunker no formato `{ "errors": [{ "message": "..." }] }`.
    static func parseBunkerErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = json["errors"] as? [[String: Any]],
            let first = errors.first,
            let message = first["message"] as? String,
            !message.isEmpty
        else {
            return nil
        }
        return message
    }

    /// Converte status HTTP + body em erro tipado (auth → `.unauthorized`).
    static func fromHTTP(statusCode: Int, data: Data) -> NetworkError {
        let body = String(data: data, encoding: .utf8)
        let bunkerMessage = parseBunkerErrorMessage(from: data)
        let combined = bunkerMessage ?? body

        if statusCode == 401 || statusCode == 403 || isAccessKeyOrAuthFailure(combined) {
            return .unauthorized
        }

        if let bunkerMessage {
            return .serverError(bunkerMessage)
        }

        return .requestFailed(statusCode, body)
    }
}

extension Error {
    var requiresSessionLogout: Bool {
        if let networkError = self as? NetworkError {
            return networkError.requiresLogout
        }
        return NetworkError.isAccessKeyOrAuthFailure(localizedDescription)
    }
}
