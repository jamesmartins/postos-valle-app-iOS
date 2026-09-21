import Foundation

struct AppConfigResponseDTO: Codable {
    let novoMenu: NovoMenuConfigDTO?
}

struct NovoMenuConfigDTO: Codable {
    let pagina: String?
    let tituloPagina: String?
    let links: [String: String]?
}
