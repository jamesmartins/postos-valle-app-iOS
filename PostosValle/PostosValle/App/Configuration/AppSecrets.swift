import Foundation

enum AppSecrets {
    
    static var authorizationCode: String {
        if let code = loadAuthorizationCodeFromBundle(), !code.isEmpty {
            return code
        }
        AppLogger.warning(
            .app,
            "Secrets.plist ausente no bundle ou authorizationCode vazio. " +
            "Crie PostosValle/Secrets.plist a partir de Secrets.example.plist e faça um Clean Build."
        )
        return ""
    }

    /// Garante padding Base64 ("==") quando exigido pelo backend
    static var authorizationCodePadded: String {
        let value = authorizationCode
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private static func loadAuthorizationCodeFromBundle() -> String? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            Bundle.main.url(forResource: "Secrets", withExtension: "plist", subdirectory: nil)
        ]

        for case let url? in candidates {
            if let dict = NSDictionary(contentsOf: url) as? [String: Any],
               let code = dict["authorizationCode"] as? String {
                let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "REPLACE_WITH_AUTHORIZATION_CODE" {
                    return trimmed
                }
            }
        }
        return nil
    }
}
