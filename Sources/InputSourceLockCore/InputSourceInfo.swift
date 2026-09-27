import Foundation

public struct InputSourceInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let isSelectCapable: Bool
    public let isEnabled: Bool
    public let category: String
    public let type: String

    public init(
        id: String,
        name: String,
        bundleID: String,
        isSelectCapable: Bool = true,
        isEnabled: Bool = true,
        category: String = "TISCategoryKeyboardInputSource",
        type: String = "TISTypeKeyboardLayout"
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.isSelectCapable = isSelectCapable
        self.isEnabled = isEnabled
        self.category = category
        self.type = type
    }
}
