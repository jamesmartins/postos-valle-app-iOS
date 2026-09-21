import Foundation

enum AppSecrets {
    /// Lê `authorizationCode` de `Secrets.plist` (não versionado).
    static var authorizationCode: String {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let code = dict["authorizationCode"] as? String,
           !code.isEmpty,
           code != "REPLACE_WITH_AUTHORIZATION_CODE" {
            return code
        }
        AppLogger.warning(.app, "Secrets.plist ausente ou inválido — authorizationCode vazio")
        return ""
    }

    /// Garante padding Base64 ("==") quando exigido pelo backend (ex: APP.do)
    static var authorizationCodePadded: String {
        let value = authorizationCode
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }
}
