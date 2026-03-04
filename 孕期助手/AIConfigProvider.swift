import Foundation

enum AIConfigProvider {
    struct EnvironmentOverrides {
        var baseURL: String?
        var apiKey: String?
        var model: String?
    }

    static let bundledDefaultBaseURL = "https://pregnancy-ai-backend.onrender.com"
    static let bundledDefaultBackendToken = "ac0d99c5f21eb1e95a5c28bdcef0e0caf458b9c2b5a49da2cca82a0c5d0d3ac5"
    static let fallbackModel = "gemini-2.5-flash"

    static func environmentOverrides() -> EnvironmentOverrides {
        let env = ProcessInfo.processInfo.environment

        let baseURL = firstNonEmpty([
            env["AI_BACKEND_URL"],
            env["AI_BACKEND_BASE_URL"],
            env["AI_BASE_URL"]
        ])?.trimmingCharacters(in: .whitespacesAndNewlines)

        let apiKey = firstNonEmpty([
            env["AI_BACKEND_TOKEN"],
            env["AI_API_KEY"]
        ])?.trimmingCharacters(in: .whitespacesAndNewlines)

        let model = firstNonEmpty([
            env["AI_BACKEND_MODEL"],
            env["AI_MODEL"]
        ])?.trimmingCharacters(in: .whitespacesAndNewlines)

        return EnvironmentOverrides(
            baseURL: (baseURL?.isEmpty == false) ? baseURL : nil,
            apiKey: (apiKey?.isEmpty == false) ? apiKey : nil,
            model: (model?.isEmpty == false) ? model : nil
        )
    }

    static func defaultConfig() -> AIConfig {
        let baseURL = appLevelDefaultValue(for: "AI_BACKEND_URL")
        let apiKey = appLevelDefaultValue(for: "AI_BACKEND_TOKEN")
        let model = appLevelDefaultValue(for: "AI_BACKEND_MODEL")
        return AIConfig(
            baseURL: baseURL.isEmpty ? bundledDefaultBaseURL : baseURL,
            apiKey: apiKey.isEmpty ? bundledDefaultBackendToken : apiKey,
            model: model.isEmpty ? fallbackModel : model
        )
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func appLevelDefaultValue(for key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
