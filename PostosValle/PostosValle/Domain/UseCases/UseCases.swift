import Foundation

struct FetchDadosComprasUseCase {
    private let repository: DadosComprasRepositoryProtocol

    init(repository: DadosComprasRepositoryProtocol) {
        self.repository = repository
    }

    func execute(cpf: String, pagina: Int = 1) async throws -> DadosComprasDashboard {
        let cleanedCPF = cpf.filter(\.isNumber)
        guard !cleanedCPF.isEmpty else {
            throw NetworkError.invalidParameters("CPF inválido ou não informado.")
        }
        return try await repository.fetchDadosCompras(cpf: cleanedCPF, pagina: pagina)
    }
}

struct FetchAppConfigUseCase {
    private let repository: AppConfigRepositoryProtocol

    init(repository: AppConfigRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [String: String] {
        try await repository.fetchAppConfig()
    }
}

struct ConsultCliUseCase {
    private let repository: ConsultaCliRepositoryProtocol

    init(repository: ConsultaCliRepositoryProtocol) {
        self.repository = repository
    }

    func execute(userID: String) async throws -> String? {
        let userIDBase64 = Data(userID.utf8).base64EncodedString()
        return try await repository.consultCli(userIDBase64: userIDBase64)
    }
}

struct ManageSessionUseCase {
    private let repository: SessionRepositoryProtocol

    init(repository: SessionRepositoryProtocol) {
        self.repository = repository
    }

    func currentSession() -> UserSession {
        repository.getSession()
    }

    func save(cpf: String) {
        let digits = cpf.filter(\.isNumber)
        if digits.count >= 10 && digits.count <= 11 {
            repository.save(cpf: digits)
        }
    }

    func save(idU: String) {
        repository.save(idU: idU)
    }

    func save(idL: String) {
        repository.save(idL: idL)
    }

    func save(userName: String) {
        repository.save(userName: userName)
    }

    func logout() {
        repository.clearSession()
    }

    /// Limpa UserDefaults + cookies/cache da WebView.
    func logoutCompletely() async {
        repository.clearSession()
        await repository.clearWebsiteData()
        AppLogger.logSuccess(.auth, operation: "ManageSessionUseCase.logoutCompletely", details: "Dados do usuário removidos do app")
    }
}
