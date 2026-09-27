# 本机 TIS 输入来源采样

2026-09-27 在 macOS 图形登录会话中，通过 Carbon 的 `TISCopyCurrentKeyboardInputSource`、`TISCreateInputSourceList` 和 `TISGetInputSourceProperty` 读取。这里只记录输入来源名称与 ID，不含键盘输入内容。其他机器或系统版本请运行：

```bash
swift scripts/dump_tis.swift
```

## 当时的结果

当前来源：`com.tencent.inputmethod.wetype.pinyin`（微信输入法）。

| 输入来源 ID | 名称 | Bundle ID | 类型 | 已启用 | 可选择 |
| --- | --- | --- | --- | --- | --- |
| `com.apple.keylayout.British` | British | `com.apple.keyboardlayout.all` | `TISTypeKeyboardLayout` | 是 | 是 |
| `com.tencent.inputmethod.wetype.pinyin` | 微信输入法 | `com.tencent.inputmethod.wetype` | `TISTypeKeyboardInputMode` | 是 | 是 |
| `com.tencent.inputmethod.wetype` | 微信输入法 | `com.tencent.inputmethod.wetype` | `TISTypeKeyboardInputMethodModeEnabled` | 是 | 否 |

微信输入法可直接选中的来源是 `.pinyin` 模式，父来源不可直接选中。工具因此按具体来源 ID 判断，调用 `TISSelectInputSource` 时只选择已启用且可选择的来源。

## 设计推论与未完成验证

Apple 多个键盘布局共用 `com.apple.keyboardlayout.all`；系统拼音、双拼、五笔等模式也可能共用一个输入法 bundle。因此 bundle ID 不能直接代表用户要锁的单一输入法来源。

这次采样确认微信输入法的 TIS 来源结构，**没有测试真实 Shift 中英文切换**。如果某个输入法在切内部模式时会改变 TIS 来源，应由用户把需要共存的来源手动加入允许列表。

注：`defaults read com.apple.HIToolbox AppleEnabledInputSources` 与沙盒中的 TIS 查询曾显示不同结果；本文件采用正常图形登录会话中的 TIS API 返回值。沙盒查询当时出现 `com.apple.hiservices-xpcservice` 连接错误。
