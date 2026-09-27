import Carbon
import Foundation

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
    return Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue() == kCFBooleanTrue
}

let filter: [CFString: Any] = [
    kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any
]
let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
let currentID = current.flatMap { stringProperty($0, kTISPropertyInputSourceID) } ?? "未知"
let sources = (TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource]) ?? []

print("采样时间: \(ISO8601DateFormatter().string(from: Date()))")
print("当前输入来源: \(currentID)")
print("已启用的键盘输入来源（ID | 名称 | Bundle ID | 类型 | 可选择）：")
for source in sources.sorted(by: {
    (stringProperty($0, kTISPropertyInputSourceID) ?? "") <
    (stringProperty($1, kTISPropertyInputSourceID) ?? "")
}) {
    guard boolProperty(source, kTISPropertyInputSourceIsEnabled) else { continue }
    let fields = [
        stringProperty(source, kTISPropertyInputSourceID) ?? "未知",
        stringProperty(source, kTISPropertyLocalizedName) ?? "未知",
        stringProperty(source, kTISPropertyBundleID) ?? "无",
        stringProperty(source, kTISPropertyInputSourceType) ?? "未知",
        boolProperty(source, kTISPropertyInputSourceIsSelectCapable) ? "是" : "否"
    ]
    print(fields.joined(separator: " | "))
}
