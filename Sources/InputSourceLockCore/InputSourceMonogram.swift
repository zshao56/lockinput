import Foundation

public enum InputSourceMonogram {
    public static func letter(name: String?, id: String?) -> String {
        if let name, let initial = initial(from: name) {
            return initial
        }

        guard let id else { return "?" }
        let lowercasedID = id.lowercased()
        if lowercasedID.contains("wetype") { return "W" }
        if lowercasedID.contains("doubao") { return "D" }

        return initial(from: id.split(separator: ".").last.map(String.init) ?? "") ?? "?"
    }

    private static func initial(from text: String) -> String? {
        let transliterated = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.toLatin, reverse: false)?
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        guard let scalar = transliterated?.unicodeScalars.first(where: {
            CharacterSet.letters.contains($0)
        }) else {
            return nil
        }
        return String(scalar).uppercased()
    }
}
