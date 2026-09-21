import SwiftUI
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var userName: String
    @Published var firstName: String
    @Published var availableBalance: Double = 0.0
    @Published var redeemedBalance: Double = 0.0
    @Published var expiredBalance: Double = 0.0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedWebItem: (url: URL, title: String, isLogout: Bool)?

    private let fetchDadosComprasUseCase: FetchDadosComprasUseCase
    private let fetchAppConfigUseCase: FetchAppConfigUseCase
    private let consultCliUseCase: ConsultCliUseCase
    private let sessionUseCase: ManageSessionUseCase

    private(set) var menuLinks: [String: String] = [:]
    var onLogout: (() -> Void)?
    private var isCompletingLogout = false

    init(
        fetchDadosComprasUseCase: FetchDadosComprasUseCase,
        fetchAppConfigUseCase: FetchAppConfigUseCase,
        consultCliUseCase: ConsultCliUseCase,
        sessionUseCase: ManageSessionUseCase
    ) {
        self.fetchDadosComprasUseCase = fetchDadosComprasUseCase
        self.fetchAppConfigUseCase = fetchAppConfigUseCase
        self.consultCliUseCase = consultCliUseCase
        self.sessionUseCase = sessionUseCase

        let session = sessionUseCase.currentSession()
        let cached = session.userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if Self.isPlausibleDisplayName(cached) {
            self.userName = cached
            self.firstName = Self.capitalizePersonName(Self.extractFirstName(from: cached))
        } else {
            // Evita saudação com login Bunker persistido
            self.userName = "Cliente"
            self.firstName = "Cliente"
            if !cached.isEmpty {
                AppLogger.warning(.app, "userName em cache ignorado: '\(cached)'")
            }
        }
    }

    var greeting: String {
        "Olá, \(firstName)!"
    }

    var canGenerateToken: Bool {
        availableBalance > 0
    }

    func formattedCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.currencySymbol = "R$"
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "R$%.2f", value)
    }

    /// Exibe saldo no formato da Home Postos Valle (`PONTOS: 0`).
    func formattedPoints(_ value: Double) -> String {
        "PONTOS: \(formattedPointsValue(value))"
    }

    func formattedPointsValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    func loadData() {
        let session = sessionUseCase.currentSession()

        Task {
            await loadMenuLinks()
        }

        guard let cpf = session.cpf, !cpf.isEmpty else {
            // Sem CPF não dá para consultar dadoscompras — tenta só o fallback de perfil.
            errorMessage = "CPF não encontrado na sessão."
            if let idU = session.idU {
                Task { await loadNameFromConsultaCliIfNeeded(idU: idU) }
            }
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            var resolvedNameFromCompras = false

            do {
                let dashboard = try await fetchDadosComprasUseCase.execute(cpf: cpf, pagina: 1)
                self.isLoading = false

                if let cliente = dashboard.cliente {
                    resolvedNameFromCompras = self.applyClienteFromCompras(cliente)
                }

                if let saldo = dashboard.saldo {
                    self.availableBalance = saldo.disponivel
                    self.redeemedBalance = saldo.resgatado
                    self.expiredBalance = saldo.expirado
                    AppLogger.info(
                        .app,
                        "Home saldo aplicado → disponível: \(saldo.disponivel), resgatado: \(saldo.resgatado), expirado: \(saldo.expirado)"
                    )
                } else {
                    AppLogger.warning(.app, "dadoscompras retornou sem objeto saldo")
                }
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                AppLogger.logFailure(.app, operation: "HomeViewModel.loadData", error: error)
            }

            // ConsultaCli só como fallback — nunca em paralelo, para não sobrescrever
            // o nome real (ex.: "Diego") com o login do Bunker (ex.: "ovppyo").
            if !resolvedNameFromCompras, let idU = session.idU {
                await loadNameFromConsultaCliIfNeeded(idU: idU)
            }
        }
    }

    /// Aplica nome vindo de `dadoscompras` (fonte preferencial da saudação).
    @discardableResult
    private func applyClienteFromCompras(_ cliente: Cliente) -> Bool {
        let fullName = cliente.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let primeiro = cliente.primeiroNome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !primeiro.isEmpty, Self.isPlausibleDisplayName(primeiro) {
            firstName = Self.capitalizePersonName(primeiro)
            userName = fullName.isEmpty ? primeiro : fullName
            sessionUseCase.save(userName: userName)
            AppLogger.info(.app, "Home nome via dadoscompras.primeiro_nome: '\(firstName)'")
            return true
        }

        if !fullName.isEmpty, Self.isPlausibleDisplayName(fullName) {
            applyUserName(fullName)
            sessionUseCase.save(userName: userName)
            AppLogger.info(.app, "Home nome via dadoscompras.nome: '\(firstName)'")
            return true
        }

        AppLogger.warning(.app, "dadoscompras sem nome utilizável (nome='\(fullName)', primeiro='\(primeiro)')")
        return false
    }

    /// Fallback quando `dadoscompras` não trouxe nome. Não sobrescreve nome já válido.
    private func loadNameFromConsultaCliIfNeeded(idU: String) async {
        if Self.isPlausibleDisplayName(firstName), firstName != "Cliente" {
            return
        }

        do {
            guard let name = try await consultCliUseCase.execute(userID: idU) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isPlausibleDisplayName(trimmed) else {
                AppLogger.warning(.app, "ConsultaCli ignorado — nome improváável: '\(trimmed)'")
                return
            }
            applyUserName(trimmed)
            sessionUseCase.save(userName: userName)
            AppLogger.info(.app, "Home nome via ConsultaCli (fallback): '\(firstName)'")
        } catch {
            AppLogger.logFailure(.app, operation: "HomeViewModel.ConsultaCli", error: error)
        }
    }

    private func loadMenuLinks() async {
        do {
            self.menuLinks = try await fetchAppConfigUseCase.execute()
        } catch {
            AppLogger.logFailure(.app, operation: "HomeViewModel.loadMenuLinks", error: error)
        }
    }

    func applyUserName(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userName = trimmed
        firstName = Self.capitalizePersonName(Self.extractFirstName(from: trimmed))
    }

    private static func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Cliente" }
        return trimmed.components(separatedBy: .whitespaces).first ?? trimmed
    }

    /// Rejeita logins/usuários Bunker (ex.: "ovppyo") e lixo sem letras.
    private static func isPlausibleDisplayName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }

        // Login tipicamente tudo minúsculo, sem espaço e sem acento de nome próprio.
        let hasSpace = trimmed.contains(where: { $0.isWhitespace })
        let letters = trimmed.filter { $0.isLetter }
        let lowercaseRatio = letters.isEmpty
            ? 0.0
            : Double(letters.filter { $0.isLowercase }.count) / Double(letters.count)

        if !hasSpace, letters.count >= 4, lowercaseRatio == 1.0, !trimmed.contains(where: { $0 == " " }) {
            // "diego" ok se for curto? Preferimos aceitar se parece nome comum com capitalização depois.
            // Bloqueia padrões claramente de login: sem maiúscula e sem vogal acentuada / parece handle.
            let vowels = CharacterSet(charactersIn: "aeiouAEIOUáàâãéêíóôõúÁÀÂÃÉÊÍÓÔÕÚ")
            let vowelCount = trimmed.unicodeScalars.filter { vowels.contains($0) }.count
            // Handles curtos só com minúsculas (ex.: ovppyo) — rejeitar.
            if vowelCount <= 2, trimmed.count <= 8 {
                return false
            }
        }

        return true
    }

    private static func capitalizePersonName(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    func handleMenuItemSelection(_ item: HomeMenuItem) {
        AppLogger.info(.app, "Navegação: item selecionado: '\(item.rawValue)'")

        if item == .logout {
            openLogout()
            return
        }

        let session = sessionUseCase.currentSession()

        if let linkKey = item.novoMenuLinkKey, let rawURL = menuLinks[linkKey] {
            if let builtURL = BunkerURLBuilder.build(from: rawURL, idU: session.idU) {
                selectedWebItem = (url: builtURL, title: item.rawValue, isLogout: false)
                return
            }
        }

        let fallbackBase: String
        switch item {
        case .profile:
            fallbackBase = "\(AppConstants.bunkerAppHost)/app/cadastro_V2.do"
        case .statement:
            fallbackBase = "\(AppConstants.bunkerAppHost)/app/relCompras.do"
        case .prizes:
            fallbackBase = "\(AppConstants.bunkerAppHost)/app/premios.do"
        case .addresses:
            fallbackBase = "\(AppConstants.bunkerAppHost)/app/regioes.do"
        case .contact:
            fallbackBase = "\(AppConstants.bunkerAppHost)/app/faleConosco.do"
        case .logout:
            return
        }

        let builtURL = BunkerURLBuilder.build(from: fallbackBase, idU: session.idU)
        if let url = builtURL {
            selectedWebItem = (url: url, title: item.rawValue, isLogout: false)
        } else {
            errorMessage = "Link temporariamente indisponível para \(item.rawValue)."
        }
    }

    /// Abre o link `logout` do APP.do (intro.do + token) antes de limpar a sessão local.
    private func openLogout() {
        let session = sessionUseCase.currentSession()

        if let rawURL = menuLinks["logout"],
           let builtURL = BunkerURLBuilder.build(from: rawURL, idU: session.idU) {
            AppLogger.info(.auth, "🚪 Logout via link do APP.do: \(builtURL.absoluteString)")
            selectedWebItem = (url: builtURL, title: "Sair", isLogout: true)
            return
        }

        // Se os links ainda não carregaram, tenta buscar APP.do e abrir em seguida
        Task {
            await loadMenuLinks()
            let refreshed = sessionUseCase.currentSession()
            if let rawURL = self.menuLinks["logout"],
               let builtURL = BunkerURLBuilder.build(from: rawURL, idU: refreshed.idU) {
                AppLogger.info(.auth, "🚪 Logout via link do APP.do (após refresh): \(builtURL.absoluteString)")
                self.selectedWebItem = (url: builtURL, title: "Sair", isLogout: true)
            } else if let fallback = AppRuntimeConfig.shared.dynamicLoginURL
                        ?? URL(string: AppConstants.loginURLString) {
                AppLogger.warning(.auth, "⚠️ Link logout indisponível; usando login como fallback: \(fallback.absoluteString)")
                self.selectedWebItem = (url: fallback, title: "Sair", isLogout: true)
            } else {
                await self.completeLogout()
            }
        }
    }

    /// Chamado ao concluir (ou falhar) a WebView de logout.
    func completeLogout() async {
        guard !isCompletingLogout else { return }
        isCompletingLogout = true
        selectedWebItem = nil
        await sessionUseCase.logoutCompletely()
        resetLocalState()
        onLogout?()
        isCompletingLogout = false
    }

    private func resetLocalState() {
        userName = "Cliente"
        firstName = "Cliente"
        availableBalance = 0
        redeemedBalance = 0
        expiredBalance = 0
        errorMessage = nil
        menuLinks = [:]
    }

    func openGenerateToken() {
        guard canGenerateToken else { return }
        let tokenT = AppConstants.HardcodedLinks.tokenT
        guard !tokenT.isEmpty else {
            errorMessage = "Link de Gerar Token ainda não configurado."
            return
        }
        let session = sessionUseCase.currentSession()
        let tokenURL = BunkerURLBuilder.build(
            from: "\(AppConstants.HardcodedLinks.tokenBase)?t=\(tokenT)",
            idU: session.idU
        )

        if let url = tokenURL {
            selectedWebItem = (url: url, title: "Gerar Token", isLogout: false)
        }
    }
}
