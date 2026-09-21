import SwiftUI

enum PostosValleColors {
    /// Verde principal Postos Valle (~#82BC41) — fundo da Home
    static let brandGreen = Color(red: 0.51, green: 0.74, blue: 0.25)

    /// Alias: Home usa o verde da marca
    static let primaryBlue = brandGreen

    /// Cards Resgatado / Expirado (verde mais escuro, só leitura)
    static let darkCardBlue = Color(red: 0.35, green: 0.55, blue: 0.15).opacity(0.90)

    /// Navy dos tiles / botões (~#302D7D)
    static let navy = Color(red: 0.19, green: 0.18, blue: 0.49)

    /// Teal de links / destaques (~#4DB6AC)
    static let accentTeal = Color(red: 0.30, green: 0.71, blue: 0.67)

    /// Alias legado usado em CTAs
    static let accentYellow = accentTeal

    /// Fundo dos tiles do menu
    static let tileBackground = Color(red: 0.93, green: 0.96, blue: 0.90)

    /// Ícones e textos dos tiles
    static let tileForeground = navy

    /// Fundo do aviso de token
    static let tokenBarBackground = Color(red: 0.90, green: 0.95, blue: 0.85)

    /// Texto do aviso de token
    static let tokenBarForeground = Color(red: 0.25, green: 0.42, blue: 0.10)

    static let backgroundWhite = Color.white
    static let textSecondary = Color.white.opacity(0.85)
}
