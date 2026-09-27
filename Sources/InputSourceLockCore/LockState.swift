import Foundation

public struct LockState: Codable, Equatable, Sendable {
    public var primaryID: String?
    public var allowedIDs: Set<String>
    public var lastMemberID: String?
    public var isLocked: Bool
    public var isPaused: Bool
    public var pauseReason: String?

    public init(
        primaryID: String? = nil,
        allowedIDs: Set<String> = [],
        lastMemberID: String? = nil,
        isLocked: Bool = false,
        isPaused: Bool = false,
        pauseReason: String? = nil
    ) {
        self.primaryID = primaryID
        self.allowedIDs = allowedIDs
        self.lastMemberID = lastMemberID
        self.isLocked = isLocked
        self.isPaused = isPaused
        self.pauseReason = pauseReason
    }

    enum CodingKeys: String, CodingKey {
        case primaryID
        case allowedIDs
        case lastMemberID
        case isLocked
        case isPaused
        case pauseReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primaryID = try container.decodeIfPresent(String.self, forKey: .primaryID)
        let allowedList = try container.decodeIfPresent([String].self, forKey: .allowedIDs) ?? []
        self.allowedIDs = Set(allowedList)
        self.lastMemberID = try container.decodeIfPresent(String.self, forKey: .lastMemberID)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        self.pauseReason = try container.decodeIfPresent(String.self, forKey: .pauseReason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(primaryID, forKey: .primaryID)
        try container.encode(Array(allowedIDs).sorted(), forKey: .allowedIDs)
        try container.encodeIfPresent(lastMemberID, forKey: .lastMemberID)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encodeIfPresent(pauseReason, forKey: .pauseReason)
    }
}
