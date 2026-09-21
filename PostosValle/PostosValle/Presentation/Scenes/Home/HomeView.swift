import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    private let menuItems = HomeMenuItem.allCases

    var body: some View {
        ZStack(alignment: .top) {
            PostosValleColors.brandGreen.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                    // Resgatado / Expirado — somente visualização
                    summaryRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    tokenBarView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                }

                menuSheet
            }

            if viewModel.isLoading {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }
        }
        .onAppear {
            viewModel.loadData()
        }
        .fullScreenCover(item: Binding(
            get: {
                if let item = viewModel.selectedWebItem {
                    return WebSheetItem(url: item.url, title: item.title, isLogout: item.isLogout)
                }
                return nil
            },
            set: { newValue in
                if newValue == nil, viewModel.selectedWebItem?.isLogout == true {
                    Task { await viewModel.completeLogout() }
                } else {
                    viewModel.selectedWebItem = nil
                }
            }
        )) { sheetItem in
            WebDetailSheetView(
                url: sheetItem.url,
                title: sheetItem.title,
                isLogoutFlow: sheetItem.isLogout,
                onDismiss: {
                    if sheetItem.isLogout {
                        Task { await viewModel.completeLogout() }
                    } else {
                        viewModel.selectedWebItem = nil
                    }
                }
            )
        }
    }

    // MARK: - Subviews

    private var topSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.greeting)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Saldo disponível")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PostosValleColors.textSecondary)
                    .padding(.top, 2)

                Text(viewModel.formattedPoints(viewModel.availableBalance))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("LogoPostosValleBadge")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            SummaryCardView(
                title: "Resgatado",
                value: viewModel.formattedPointsValue(viewModel.redeemedBalance)
            )

            SummaryCardView(
                title: "Expirado",
                value: viewModel.formattedPointsValue(viewModel.expiredBalance)
            )
        }
    }

    @ViewBuilder
    private var tokenBarView: some View {
        if viewModel.canGenerateToken {
            Button(action: viewModel.openGenerateToken) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .bold))
                    Text("Gerar Token")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(PostosValleColors.brandGreen)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            }
        } else {
            Text("Ainda não há saldo para gerar tokens")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PostosValleColors.tokenBarForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(PostosValleColors.tokenBarBackground)
                .cornerRadius(8)
        }
    }

    private var menuSheet: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                menuGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.white
                .cornerRadius(28, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var menuGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(menuItems) { item in
                MenuTileView(
                    title: item.rawValue,
                    iconName: item.systemImage,
                    action: {
                        viewModel.handleMenuItemSelection(item)
                    }
                )
            }
        }
    }
}

private struct WebSheetItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let isLogout: Bool
}

#Preview {
    HomeView(
        viewModel: HomeViewModel(
            fetchDadosComprasUseCase: FetchDadosComprasUseCase(repository: DadosComprasRepository()),
            fetchAppConfigUseCase: FetchAppConfigUseCase(repository: AppConfigRepository()),
            consultCliUseCase: ConsultCliUseCase(repository: ConsultaCliRepository()),
            sessionUseCase: ManageSessionUseCase(repository: SessionRepository())
        )
    )
}
