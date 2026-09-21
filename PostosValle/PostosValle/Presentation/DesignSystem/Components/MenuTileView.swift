import SwiftUI

struct MenuTileView: View {
    let title: String
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(PostosValleColors.tileForeground)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PostosValleColors.tileForeground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(PostosValleColors.tileBackground)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
