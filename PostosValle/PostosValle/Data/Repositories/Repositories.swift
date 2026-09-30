import Foundation
import WebKit

final class DadosComprasRepository: DadosComprasRepositoryProtocol {
    private let client: HTTPClientProtocol

    init(client: HTTPClientProtocol = HTTPClient.shared) {
        self.client = client
    }

    func fetchDadosCompras(cpf: String, pagina: Int) async throws -> DadosComprasDashboard {
        let maskedCPF = maskCPF(cpf)
        AppLogger.info(.repository, "Buscando dados de compras para CPF: \(maskedCPF) (página: \(pagina))...")

        let endpoint = Endpoint(
            urlString: AppConstants.dadosComprasURLString,
            method: .POST,
            headers: [
                "authorizationCode": AppSecrets.authorizationCode
            ],
            parameters: [
                "NUM_CGCECPF": cpf,
                "pagina": pagina
            ]
        )

        do {
            let response: DadosComprasResponseDTO = try await client.request(endpoint)

            guard response.coderro.value == 200 else {
                let error = NetworkError.serverError(response.msgerro)
                AppLogger.logFailure(
                    .repository,
                    operation: "DadosComprasRepository.fetchDadosCompras",
                    error: error,
                    details: "coderro: \(response.coderro.value), msgerro: \(response.msgerro)"
                )
                throw error
            }

            let cliente = response.cliente?.toDomain()
            let saldo = response.saldo?.toDomain()
            let compras = response.compras?.map { $0.toDomain() } ?? []

            let resumo = """
            Cliente: '\(cliente?.nome ?? "N/A")', \
            Disponível: \(saldo?.disponivel ?? 0), \
            Resgatado: \(saldo?.resgatado ?? 0), \
            Expirado: \(saldo?.expirado ?? 0), \
            Movimentos: \(compras.count)
            """
            AppLogger.logSuccess(.repository, operation: "DadosComprasRepository.fetchDadosCompras", details: resumo)

            if let saldo, saldo.resgatado == 0, saldo.expirado == 0, saldo.disponivel == 0 {
                AppLogger.warning(.repository, "⚠️ Saldo decodificado zerado — confira o JSON bruto no log de Network.")
            }

            return DadosComprasDashboard(cliente: cliente, saldo: saldo, compras: compras)
        } catch {
            AppLogger.logFailure(.repository, operation: "DadosComprasRepository.fetchDadosCompras", error: error)
            throw error
        }
    }

    private func maskCPF(_ cpf: String) -> String {
        let digits = cpf.filter(\.isNumber)
        guard digits.count >= 6 else { return "***" }
        let prefix = digits.prefix(3)
        let suffix = digits.suffix(2)
        return "\(prefix).***.***-\(suffix)"
    }
}

final class AppConfigRepository: AppConfigRepositoryProtocol {
    private let client: HTTPClient
    private let defaults: UserDefaults
    private static let cacheKey = "postos_valle.cached_app_do_links"
    /// Evita N chamadas paralelas a APP.do (bootstrap + Home).
    private static var inFlight: Task<[String: String], Error>?

    init(
        client: HTTPClient = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
    }

    func fetchAppConfig() async throws -> [String: String] {
        if let inFlight = Self.inFlight {
            AppLogger.info(.repository, "APP.do já em andamento — reutilizando a mesma Task")
            return try await inFlight.value
        }

        let task = Task<[String: String], Error> {
            try await self.performFetchWithRetryAndCache()
        }
        Self.inFlight = task
        defer { Self.inFlight = nil }

        return try await task.value
    }

    private func performFetchWithRetryAndCache() async throws -> [String: String] {
        AppLogger.info(.repository, "Carregando configurações e links de menu do APP.do...")

        let auth = AppSecrets.authorizationCodePadded
        guard !auth.isEmpty else {
            if let cached = loadCachedLinks() {
                AppLogger.warning(.repository, "authorizationCode vazio — usando cache APP.do (\(cached.count) links)")
                await applyLinks(cached)
                return cached
            }
            throw NetworkError.invalidParameters("authorizationCode ausente no Secrets.plist")
        }

        let endpoint = Endpoint(
            urlString: AppConstants.appConfigURLString,
            method: .GET,
            headers: [
                "authorizationCode": auth
            ],
            parameters: nil,
            timeoutInterval: 15
        )

        do {
            let response: AppConfigResponseDTO = try await client.requestWithRetry(endpoint, attempts: 3)
            let links = response.novoMenu?.links ?? [:]
            let keys = links.keys.sorted().joined(separator: ", ")

            await applyLinks(links)
            persistLinks(links)

            AppLogger.logSuccess(
                .repository,
                operation: "AppConfigRepository.fetchAppConfig",
                details: "Foram carregados \(links.count) links do menu: [\(keys)]"
            )
            return links
        } catch {
            if let cached = loadCachedLinks(), !cached.isEmpty {
                AppLogger.warning(
                    .repository,
                    "APP.do falhou (\(error.localizedDescription)) — usando cache com \(cached.count) links"
                )
                await applyLinks(cached)
                return cached
            }

            AppLogger.logFailure(.repository, operation: "AppConfigRepository.fetchAppConfig", error: error)
            throw error
        }
    }

    private func applyLinks(_ links: [String: String]) async {
        await MainActor.run {
            AppRuntimeConfig.shared.update(from: links)
        }
    }

    private func persistLinks(_ links: [String: String]) {
        guard !links.isEmpty else { return }
        defaults.set(links, forKey: Self.cacheKey)
    }

    private func loadCachedLinks() -> [String: String]? {
        defaults.dictionary(forKey: Self.cacheKey) as? [String: String]
    }
}

final class ConsultaCliRepository: ConsultaCliRepositoryProtocol {
    private let client: HTTPClientProtocol

    init(client: HTTPClientProtocol = HTTPClient.shared) {
        self.client = client
    }

    func consultCli(userIDBase64: String) async throws -> String? {
        AppLogger.info(.repository, "Consultando perfil do cliente no ConsultaCli.do...")

        let endpoint = Endpoint(
            urlString: AppConstants.consultaCliURLString,
            method: .POST,
            headers: [
                "authorizationCode": AppSecrets.authorizationCode
            ],
            parameters: [
                "RD_userId": userIDBase64,
                "RD_userCompany": AppConstants.userCompany
            ]
        )

        do {
            let (data, _) = try await client.requestRaw(endpoint)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["RD_userName"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppLogger.logSuccess(
                    .repository,
                    operation: "ConsultaCliRepository.consultCli",
                    details: "Nome recuperado: '\(name)'"
                )
                return name
            }

            AppLogger.warning(.repository, "ConsultaCliRepository.consultCli retornou sem campo 'RD_userName' preenchido.")
            return nil
        } catch {
            AppLogger.logFailure(.repository, operation: "ConsultaCliRepository.consultCli", error: error)
            throw error
        }
    }
}

final class SessionRepository: SessionRepositoryProtocol {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func getSession() -> UserSession {
        UserSession(
            cpf: defaults.string(forKey: "cpf"),
            idU: defaults.string(forKey: "idU"),
            idL: defaults.string(forKey: "idL"),
            userName: defaults.string(forKey: "userName")
        )
    }

    func save(cpf: String) {
        defaults.set(cpf, forKey: "cpf")
        AppLogger.info(.auth, "Sessão salva: CPF persistido")
    }

    func save(idU: String) {
        defaults.set(idU, forKey: "idU")
        AppLogger.info(.auth, "Sessão salva: idU persistido")
    }

    func save(idL: String) {
        defaults.set(idL, forKey: "idL")
        AppLogger.info(.auth, "Sessão salva: idL persistido")
    }

    func save(userName: String) {
        defaults.set(userName, forKey: "userName")
        AppLogger.info(.auth, "Sessão salva: userName persistido ('\(userName)')")
    }

    func clearSession() {
        defaults.removeObject(forKey: "cpf")
        defaults.removeObject(forKey: "idU")
        defaults.removeObject(forKey: "idL")
        defaults.removeObject(forKey: "userName")
        defaults.removeObject(forKey: "login")
        defaults.removeObject(forKey: "senha")
        AppLogger.info(.auth, "Sessão limpa (Logout: UserDefaults)")
    }

    /// Remove cookies, cache e storage do WKWebView (logout completo no lado web).
    func clearWebsiteData() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        AppLogger.info(.auth, "Sessão limpa (Logout: cookies/cache WebView)")
    }
}
