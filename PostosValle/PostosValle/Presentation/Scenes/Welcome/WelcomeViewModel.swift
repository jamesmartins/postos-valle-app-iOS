import SwiftUI
import Combine

@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published var isLoading = false

    var onLoginTapped: (() -> Void)?
    var onRegisterTapped: (() -> Void)?
    var onTermsTapped: (() -> Void)?

    func login() {
        onLoginTapped?()
    }

    func register() {
        onRegisterTapped?()
    }

    func terms() {
        onTermsTapped?()
    }
}
