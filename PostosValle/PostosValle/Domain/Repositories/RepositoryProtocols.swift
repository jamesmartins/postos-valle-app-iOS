import Foundation

protocol DadosComprasRepositoryProtocol {
    func fetchDadosCompras(cpf: String, pagina: Int) async throws -> DadosComprasDashboard
}

protocol AppConfigRepositoryProtocol {
    func fetchAppConfig() async throws -> [String: String]
}

protocol ConsultaCliRepositoryProtocol {
    func consultCli(userIDBase64: String) async throws -> String?
}

protocol SessionRepositoryProtocol {
    func getSession() -> UserSession
    func save(cpf: String)
    func save(idU: String)
    func save(idL: String)
    func save(userName: String)
    func clearSession()
    func clearWebsiteData() async
}
