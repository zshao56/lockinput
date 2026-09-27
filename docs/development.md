# 开发记录

这份记录保留从需求到可构建 App 的关键决策，方便以后更换目标输入法或继续开发。

## 需求

- 初始目标：macOS 始终选用微信输入法，避免回退到系统自带输入法。
- 微信输入法自己的中英文模式切换必须保持可用。
- 后续可以改锁其他输入法，因此目标不能写死为微信输入法。
- 用 Herdr 组织流程：先确认方法，由 pi 审核，再交给 agy 实现。

参考的 InputLock 仓库只有说明文档，没有可复用的程序源码，因此本项目从零实现。

## 方法确认

1. 查看本机 `/Library/Input Methods/WeType.app/Contents/Info.plist`：微信输入法 2.2.3 声明了 `com.tencent.inputmethod.wetype.pinyin` 模式。
2. macOS SDK 的 `TextInputSources.h` 提供 `TISCopyCurrentKeyboardInputSource`、`TISCreateInputSourceList`、`TISSelectInputSource`，以及选中来源与启用来源变化通知。
3. 选择“发现来源改变后恢复”的方式。菜单栏程序无需截获所有按键；输入法内部模式若不改变 TIS 来源 ID，就不会被干预。
4. 在正常图形登录会话中调用 TIS，确认当前来源为 `com.tencent.inputmethod.wetype.pinyin`。原始采样见 [TIS 记录](tis_dump.md)，可用 `swift scripts/dump_tis.swift` 重查。

## 方案审核

pi 的审核指出，直接按 bundle ID 自动分组会误把 Apple 布局、系统拼音／双拼／五笔等不同来源视为同一个锁定目标。最终规则是：**默认只锁用户选中的具体来源 ID**；需要允许其他来源时，由用户在界面中手动添加。

最终实现还包含：约 150 ms 防抖、切换前复查、App Nap 防护、每秒最多 3 次恢复尝试、连续失败 3 次暂停。目标消失或被禁用时暂停，重新可用后继续。设置保存主要目标、额外允许项、最近使用的允许来源和锁定状态。

## 实现与复核

agy 实现了 Swift Package、菜单栏界面、TIS 适配层、状态与决策逻辑、测试及 `.app` 打包脚本。pi 的成品审核发现并要求修复两项功能问题：

| 问题 | 修复 |
| --- | --- |
| 更换主要目标后，旧目标仍留在允许列表，导致锁定失效 | 更换目标时移除旧主要来源并同步最近来源；增加连续切换目标测试 |
| 重启 App 后，已保存的锁定状态不会立即恢复目标来源 | 启动时检查当前来源并执行一次恢复决策；增加带模拟 TIS 服务的测试 |

复核时还把通知名改为使用 SDK 常量，对启用来源变化加防抖，并清理失败切换后残留的预期来源状态。pi 最终复核通过。

## 验证状态

- `./scripts/run_tests.sh`：9 组测试、65 个断言通过。
- `./scripts/build_app.sh`：Release 构建、`Info.plist` 检查、临时签名验证通过。
- 在本机启动 `dist/InputSourceLock.app` 后，进程保持运行。
- 真实按 Shift 切换微信输入法中英文并打字的体验，仍需用户在图形界面手动确认。TIS 来源结构已验证；不能把结构验证写成按键体验验收。

## v0.1.0 发布准备

根据菜单栏截图，状态区改为 macOS 模板 SF Symbol：只显示图标，不显示输入法名称；当前深色菜单栏上由系统绘制成白色。锁定、未锁定、暂停分别使用实心锁、打开的实心锁和警告图标。菜单内部仍保留状态文字与目标名称。

发行范围确定为 Apple Silicon（arm64）。`scripts/build_dmg.sh` 从源码构建 App、检查签名，再制作含 `InputSourceLock.app`、Applications 快捷方式和安装说明的 DMG。构建后做了磁盘映像校验及挂载检查。该包使用临时签名，未经过 Apple 公证。

## v0.1.1 图标调整

根据使用反馈，单独的锁形图标不够直观。菜单栏图标改为“键盘＋状态标记”：闭锁表示已锁定，开锁表示未锁定，警告标记表示暂停；仍采用 macOS 模板图像，以适应菜单栏的单色外观。发行包版本更新为 `v0.1.1`，继续仅支持 Apple Silicon。
