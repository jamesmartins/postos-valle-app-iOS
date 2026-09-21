import Foundation

enum HomeMenuItem: String, CaseIterable, Identifiable {
    case profile = "Meus Dados"
    case statement = "Extrato"
    case prizes = "Prêmios"
    case addresses = "Endereços"
    case contact = "Fale Conosco"
    case logout = "Sair"

    var id: String { rawValue }

    /// Chave correspondente no JSON retornado por `APP.do` em `novoMenu.links`
    var novoMenuLinkKey: String? {
        switch self {
        case .profile: return "meus_dados"
        case .statement: return "historico"
        case .prizes: return "premios"
        case .addresses: return "enderecos"
        case .contact: return "fale_conosco"
        case .logout: return "logout"
        }
    }

    var systemImage: String {
        switch self {
        case .profile:
            return "person.text.rectangle"
        case .statement:
            return "doc.text"
        case .prizes:
            return "gift"
        case .addresses:
            return "mappin.and.ellipse"
        case .contact:
            return "headphones"
        case .logout:
            return "rectangle.portrait.and.arrow.right"
        }
    }
}
