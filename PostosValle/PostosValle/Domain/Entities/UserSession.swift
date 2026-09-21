import Foundation

struct UserSession: Equatable {
    var cpf: String?
    var idU: String?
    var idL: String?
    var userName: String?

    var isAuthenticated: Bool {
        guard let cpf = cpf, !cpf.isEmpty else { return false }
        return idU != nil && !(idU?.isEmpty ?? true)
    }
}
