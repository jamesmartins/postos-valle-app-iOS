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
        let initialName = session.userName ?? "Cliente"
        self.userName = initialName
        self.firstName = Self.extractFirstName(from: initialName)
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

        if let idU = session.idU, session.userName == nil {
            Task {
                if let name = try? await consultCliUseCase.execute(userID: idU) {
                    self.applyUserName(name)
                    self.sessionUseCase.save(userName: name)
                }
            }
        }

        guard let cpf = session.cpf, !cpf.isEmpty else {
            errorMessage = "CPF não encontrado na sessão."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let dashboard = try await fetchDadosComprasUseCase.execute(cpf: cpf, pagina: 1)
                self.isLoading = false

                if let cliente = dashboard.cliente {
                    if let primeiroNome = cliente.primeiroNome, !primeiroNome.isEmpty {
                        self.firstName = primeiroNome
                        self.userName = cliente.nome
                    } else {
                        self.applyUserName(cliente.nome)
                    }
                    self.sessionUseCase.save(userName: self.userName)
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
        firstName = Self.extractFirstName(from: trimmed)
    }

    private static func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Cliente" }
        return trimmed.components(separatedBy: .whitespaces).first ?? trimmed
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
