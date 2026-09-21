import SwiftUI

@main
struct PostosValleApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ZStack {
                PostosValleColors.primaryBlue
                    .ignoresSafeArea()

                switch coordinator.currentRoute {
                case .login:
                    if coordinator.isLoginReady {
                        LoginWebView(
                            initialURL: coordinator.resolvedIntroURL,
                            candidateURLs: coordinator.loginCandidateURLs,
                            sessionUseCase: coordinator.manageSessionUseCase,
                            onLoginSuccess: { cpf, idU, idL in
                                coordinator.onLoginSuccess(cpf: cpf, idU: idU, idL: idL)
                            },
                            onDismiss: {},
                            onRetryFreshStart: {
                                Task { await coordinator.prepareFreshLogin() }
                            }
                        )
                        .id(coordinator.resolvedIntroURL.absoluteString)
                        .transition(.opacity)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                    }

                case .home:
                    if let homeViewModel = coordinator.homeViewModel {
                        HomeView(viewModel: homeViewModel)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: coordinator.currentRoute)
        }
    }
}
