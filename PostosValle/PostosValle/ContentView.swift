import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
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
        } else {
            ZStack {
                PostosValleColors.primaryBlue.ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
    }
}

#Preview {
    ContentView()
}
