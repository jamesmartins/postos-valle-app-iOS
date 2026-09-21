import SwiftUI

struct PostosValleButton: View {
    enum Style {
        case primaryYellow
        case secondaryWhite
        case textLinkWhite
    }

    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .primaryYellow:
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PostosValleColors.accentYellow)
                    .cornerRadius(26)
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

            case .secondaryWhite:
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)

            case .textLinkWhite:
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
            }
        }
    }
}
