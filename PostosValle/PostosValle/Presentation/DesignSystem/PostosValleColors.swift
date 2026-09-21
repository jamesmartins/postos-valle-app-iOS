import SwiftUI

enum PostosValleColors {
    /// Verde do header / branding Postos Valle (~#82BC41)
    static let brandGreen = Color(red: 0.51, green: 0.74, blue: 0.25)

    /// Roxo/navy da Home e botões (~#302D7D)
    static let primaryBlue = Color(red: 0.19, green: 0.18, blue: 0.49)

    /// Cards Resgatado / Expirado (tom mais escuro do primary)
    static let darkCardBlue = Color(red: 0.14, green: 0.13, blue: 0.38).opacity(0.90)

    /// Teal de links / destaques (~#4DB6AC)
    static let accentTeal = Color(red: 0.30, green: 0.71, blue: 0.67)

    /// Alias legado usado em CTAs amarelos do template Bunker
    static let accentYellow = accentTeal

    /// Fundo dos tiles do menu
    static let tileBackground = Color(red: 0.91, green: 0.91, blue: 0.95)

    /// Ícones e textos dos tiles
    static let tileForeground = Color(red: 0.19, green: 0.18, blue: 0.49)

    /// Fundo do aviso de token
    static let tokenBarBackground = Color(red: 0.88, green: 0.88, blue: 0.94)

    /// Texto do aviso de token
    static let tokenBarForeground = Color(red: 0.19, green: 0.18, blue: 0.49)

    static let backgroundWhite = Color.white
    static let textSecondary = Color.white.opacity(0.8)
}
