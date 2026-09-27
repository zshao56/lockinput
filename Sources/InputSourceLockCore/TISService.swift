import Foundation
import Carbon

public protocol TISServiceProtocol: Sendable {
    func getKeyboardInputSources(includeAllInstalled: Bool) -> [InputSourceInfo]
    func getCurrentKeyboardInputSource() -> InputSourceInfo?
    func selectInputSource(id: String) -> Bool
}

public final class TISService: TISServiceProtocol, @unchecked Sendable {
    public init() {}

    public func getKeyboardInputSources(includeAllInstalled: Bool = false) -> [InputSourceInfo] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        var results: [InputSourceInfo] = []
        for source in list {
            if let info = extractSourceInfo(source) {
                results.append(info)
            }
        }
        return results
    }

    public func getCurrentKeyboardInputSource() -> InputSourceInfo? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return extractSourceInfo(current)
    }

    public func selectInputSource(id: String) -> Bool {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any
        ]
        // Search enabled sources first
        if let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] {
            for source in list {
                if let sourceID = getStringProperty(source, kTISPropertyInputSourceID), sourceID == id {
                    let status = TISSelectInputSource(source)
                    return status == noErr
                }
            }
        }
        // Fallback search in all installed sources
        if let list = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource] {
            for source in list {
                if let sourceID = getStringProperty(source, kTISPropertyInputSourceID), sourceID == id {
                    let status = TISSelectInputSource(source)
                    return status == noErr
                }
            }
        }
        return false
    }

    private func extractSourceInfo(_ source: TISInputSource) -> InputSourceInfo? {
        guard let id = getStringProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let name = getStringProperty(source, kTISPropertyLocalizedName) ?? id
        let bundleID = getStringProperty(source, kTISPropertyBundleID) ?? ""
        let isSelectCapable = getBoolProperty(source, kTISPropertyInputSourceIsSelectCapable) ?? false
        let isEnabled = getBoolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false
        let category = getStringProperty(source, kTISPropertyInputSourceCategory) ?? ""
        let type = getStringProperty(source, kTISPropertyInputSourceType) ?? ""

        return InputSourceInfo(
            id: id,
            name: name,
            bundleID: bundleID,
            isSelectCapable: isSelectCapable,
            isEnabled: isEnabled,
            category: category,
            type: type
        )
    }

    private func getStringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func getBoolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }
}
