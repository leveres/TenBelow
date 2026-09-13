import Foundation

enum MediaUploadTypes {
    static func videoContentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov", "qt":
            return "video/quicktime"
        default:
            return "video/mp4"
        }
    }

    static func isLocalOnlyMediaReference(_ reference: String) -> Bool {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased().hasPrefix("file:") { return true }
        if let url = URL(string: trimmed), url.isFileURL { return true }
        return false
    }
}
