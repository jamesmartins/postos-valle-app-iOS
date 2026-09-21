import Foundation

struct ConsultaCliResponseDTO: Codable {
    let rdTokenCelular: String?
    let rdVersao: String?
    let rdUserCompany: String?
    let rdUserID: String?
    let rdUserMail: String?
    let rdUserName: String?
    let rdUserType: String?
    let rdUserpass: String?

    enum CodingKeys: String, CodingKey {
        case rdTokenCelular = "RD_TokenCelular"
        case rdVersao = "RD_Versao"
        case rdUserCompany = "RD_userCompany"
        case rdUserID = "RD_userId"
        case rdUserMail = "RD_userMail"
        case rdUserName = "RD_userName"
        case rdUserType = "RD_userType"
        case rdUserpass = "RD_userpass"
    }
}
