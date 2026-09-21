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
        case .requestFailed(let statusCode, let message):
            return message ?? "A requisição falhou com status \(statusCode)."
        case .failedDecoding(let details):
            return "Erro ao processar dados recebidos: \(details)"
        case .noData:
            return "Nenhum dado retornado pelo servidor."
        case .unauthorized:
            return "Acesso não autorizado. Verifique suas credenciais."
        case .serverError(let message):
            return message
        }
    }
}
