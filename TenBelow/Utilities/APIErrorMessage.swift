import Foundation

enum APIErrorMessage {
    static func userFacing(_ error: Error, fallback: String = "Something went wrong. Try again.") -> String {
        let nsError = error as NSError
        let raw = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        return userFacing(raw: raw, statusCode: nsError.code, fallback: fallback)
    }

    static func userFacing(raw: String, statusCode: Int? = nil, fallback: String = "Something went wrong. Try again.") -> String {
        if let parsed = parseJSONErrorField(from: raw) {
            return friendlyServerMessage(parsed, statusCode: statusCode)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return friendlyServerMessage(trimmed, statusCode: statusCode)
    }

    static func userFacingHTTP(data: Data, statusCode: Int, fallback: String = "Something went wrong. Try again.") -> String {
        let raw = String(data: data, encoding: .utf8) ?? ""
        return userFacing(raw: raw, statusCode: statusCode, fallback: fallback)
    }

    private static func parseJSONErrorField(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String else {
            return nil
        }
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func friendlyServerMessage(_ message: String, statusCode: Int?) -> String {
        let lower = message.lowercased()
        if lower.contains("authenticated user session required")
            || lower.contains("authenticated buyer session required")
            || lower.contains("authenticated seller session required") {
            return "Sign in to your account to send and receive messages."
        }
        if statusCode == 401 {
            return "Sign in to your account to continue."
        }
        if statusCode == 403 {
            return "You don't have access to this conversation."
        }
        if statusCode == 404 {
            return "This conversation could not be found."
        }
        return message
    }
}
