import SwiftUI
import Combine

@MainActor
final class LoginCoordinatorHolder: ObservableObject {
    @Published private(set) var isReady = true
    let coordinator: LoginWebCoordinator

    init(sessionUseCase: ManageSessionUseCase, candidateURLs: [URL]) {
        self.coordinator = LoginWebCoordinator(
            sessionUseCase: sessionUseCase,
            candidateURLs: candidateURLs
        )
    }
}

struct LoginWebView: View {
    let initialURL: URL
    let candidateURLs: [URL]
    let sessionUseCase: ManageSessionUseCase
    let onLoginSuccess: (_ cpf: String?, _ idU: String, _ idL: String?) -> Void
    let onDismiss: () -> Void
    var onRetryFreshStart: (() -> Void)?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @StateObject private var holder: LoginCoordinatorHolder

    init(
        initialURL: URL,
        candidateURLs: [URL] = [],
        sessionUseCase: ManageSessionUseCase,
        onLoginSuccess: @escaping (_ cpf: String?, _ idU: String, _ idL: String?) -> Void,
        onDismiss: @escaping () -> Void,
        onRetryFreshStart: (() -> Void)? = nil
    ) {
        self.initialURL = initialURL
        var all = [initialURL]
        for url in candidateURLs where !all.contains(url) {
            all.append(url)
        }
        self.candidateURLs = all
        self.sessionUseCase = sessionUseCase
        self.onLoginSuccess = onLoginSuccess
        self.onDismiss = onDismiss
        self.onRetryFreshStart = onRetryFreshStart
        _holder = StateObject(wrappedValue: LoginCoordinatorHolder(sessionUseCase: sessionUseCase, candidateURLs: all))
    }

    var body: some View {
        ZStack {
            PostosValleColors.primaryBlue.ignoresSafeArea()

            WKWebViewRepresentable(url: initialURL, coordinator: holder.coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)

            if isLoading {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }

            if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(PostosValleColors.accentYellow)

                    Text("Não foi possível carregar o login")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)

                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button(action: {
                        errorMessage = nil
                        isLoading = true
                        if let onRetryFreshStart {
                            onRetryFreshStart()
                        } else if let wv = holder.coordinator.activeWebView {
                            holder.coordinator.retry(in: wv)
                        }
                    }) {
                        Text("Tentar Novamente")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PostosValleColors.darkCardBlue)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(PostosValleColors.accentYellow)
                            .cornerRadius(10)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color.black.opacity(0.85))
                .cornerRadius(16)
                .padding(.horizontal, 28)
            }
        }
        .onAppear {
            let coord = holder.coordinator
            coord.onLoginSuccess = onLoginSuccess
            coord.onDismiss = onDismiss
            coord.onLoadingChange = { loading in
                self.isLoading = loading
            }
            coord.onErrorMessage = { msg in
                self.errorMessage = msg
            }
        }
    }
}
