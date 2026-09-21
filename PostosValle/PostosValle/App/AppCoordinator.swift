import SwiftUI
import Combine

enum AppRoute: Equatable {
    case login
    case home
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var currentRoute: AppRoute = .login
    /// Evita abrir a WebView de login antes de limpar cache e carregar APP.do.
    @Published var isLoginReady = false
    /// Mantém a Home estável — não recriar o ViewModel a cada re-render do body.
    @Published private(set) var homeViewModel: HomeViewModel?

    // Dependências Clean Architecture
    let sessionRepository: SessionRepositoryProtocol
    let dadosComprasRepository: DadosComprasRepositoryProtocol
    let appConfigRepository: AppConfigRepositoryProtocol
    let consultaCliRepository: ConsultaCliRepositoryProtocol

    let manageSessionUseCase: ManageSessionUseCase
    let fetchDadosComprasUseCase: FetchDadosComprasUseCase
    let fetchAppConfigUseCase: FetchAppConfigUseCase
    let consultCliUseCase: ConsultCliUseCase

    var resolvedIntroURL: URL {
        if let dynamic = AppRuntimeConfig.shared.dynamicLoginURL {
            return dynamic
        }
        if let candidate = AppConstants.loginCandidateURLs().first {
            return candidate
        }
        return URL(string: AppConstants.loginURLString)
            ?? URL(string: "\(AppConstants.bunkerAppHost)/app/app.do")!
    }

    var loginCandidateURLs: [URL] {
        AppConstants.loginCandidateURLs()
    }

    init(
        sessionRepository: SessionRepositoryProtocol,
        dadosComprasRepository: DadosComprasRepositoryProtocol,
        appConfigRepository: AppConfigRepositoryProtocol,
        consultaCliRepository: ConsultaCliRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.dadosComprasRepository = dadosComprasRepository
        self.appConfigRepository = appConfigRepository
        self.consultaCliRepository = consultaCliRepository

        self.manageSessionUseCase = ManageSessionUseCase(repository: sessionRepository)
        self.fetchDadosComprasUseCase = FetchDadosComprasUseCase(repository: dadosComprasRepository)
        self.fetchAppConfigUseCase = FetchAppConfigUseCase(repository: appConfigRepository)
        self.consultCliUseCase = ConsultCliUseCase(repository: consultaCliRepository)

        checkInitialRoute()
        Task { await bootstrap() }
    }

    convenience init() {
        self.init(
            sessionRepository: SessionRepository(),
            dadosComprasRepository: DadosComprasRepository(),
            appConfigRepository: AppConfigRepository(),
            consultaCliRepository: ConsultaCliRepository()
        )
    }

    private func checkInitialRoute() {
        let session = manageSessionUseCase.currentSession()
        if session.isAuthenticated {
            homeViewModel = makeHomeViewModel()
            currentRoute = .home
        } else {
            currentRoute = .login
        }
    }

    /// Limpa sessão/cache quando não autenticado e pré-carrega APP.do.
    private func bootstrap() async {
        if !manageSessionUseCase.currentSession().isAuthenticated {
            AppLogger.info(.auth, "🧹 Bootstrap: forçando limpeza de sessão/cache para recuperar o login")
            await manageSessionUseCase.logoutCompletely()
            homeViewModel = nil
            currentRoute = .login
        }

        do {
            _ = try await fetchAppConfigUseCase.execute()
            AppLogger.info(.auth, "Configurações do Bunker pré-carregadas com sucesso.")
        } catch {
            AppLogger.logFailure(.auth, operation: "AppCoordinator.bootstrap", error: error)
        }

        isLoginReady = true
    }

    /// Usado após logout ou "Tentar Novamente" no login.
    func prepareFreshLogin() async {
        isLoginReady = false
        homeViewModel = nil
        await manageSessionUseCase.logoutCompletely()
        _ = try? await fetchAppConfigUseCase.execute()
        currentRoute = .login
        isLoginReady = true
    }

    // MARK: - Transições de Fluxo

    func showLogin() {
        currentRoute = .login
    }

    func onLoginSuccess(cpf: String?, idU: String, idL: String?) {
        if let cpf = cpf {
            manageSessionUseCase.save(cpf: cpf)
        }
        manageSessionUseCase.save(idU: idU)
        if let idL = idL {
            manageSessionUseCase.save(idL: idL)
        }
        homeViewModel = makeHomeViewModel()
        withAnimation {
            currentRoute = .home
        }
    }

    // MARK: - View Factory

    func makeHomeViewModel() -> HomeViewModel {
        let vm = HomeViewModel(
            fetchDadosComprasUseCase: fetchDadosComprasUseCase,
            fetchAppConfigUseCase: fetchAppConfigUseCase,
            consultCliUseCase: consultCliUseCase,
            sessionUseCase: manageSessionUseCase
        )
        vm.onLogout = { [weak self] in
            Task { @MainActor in
                await self?.prepareFreshLogin()
            }
        }
        return vm
    }
}
