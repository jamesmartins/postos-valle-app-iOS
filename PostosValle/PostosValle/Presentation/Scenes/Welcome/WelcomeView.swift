import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel

    var body: some View {
        ZStack {
            PostosValleColors.primaryBlue
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo Postos Valle (idêntico à IMG_0106)
                Image("LogoPostosValleBadge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)

                Spacer()

                // Ações de entrada
                VStack(spacing: 16) {
                    PostosValleButton(
                        title: "LOGIN",
                        style: .primaryYellow,
                        action: viewModel.login
                    )

                    PostosValleButton(
                        title: "CADASTRE-SE",
                        style: .secondaryWhite,
                        action: viewModel.register
                    )

                    PostosValleButton(
                        title: "TERMOS E CONDIÇÕES",
                        style: .textLinkWhite,
                        action: viewModel.terms
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

#Preview {
    WelcomeView(viewModel: WelcomeViewModel())
}
