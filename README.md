# BoardLock

一个 macOS 菜单栏小工具：锁定你选中的**输入来源**。当系统或其他应用切到别的输入法时，它会把输入来源切回目标；输入法内部的中英文切换由输入法自己处理。

GitHub 仓库和 App 名称均为 `BoardLock`。最初针对微信输入法开发，也可以在菜单中改选其他输入法。

## 下载与安装

支持 **Apple Silicon（M 芯片）**、macOS 13 或更新版本。从 [GitHub Releases](https://github.com/zshao56/boardlock/releases/latest) 下载已发布版本的 DMG，打开后将 App 拖入 Applications。本仓库可用 `./scripts/build_dmg.sh` 构建包含首字母图标的 `BoardLock-v0.1.3-arm64.dmg`。如果已安装旧版 `InputSourceLock.app`，请先退出并移走，避免两个版本同时运行；原有锁定设置会沿用。

App 只在菜单栏显示一个单色图标，不占用 Dock。图标用主要输入法名称的首字母（中文按拼音取首字母）加状态标记：例如微信输入法为 W＋锁，豆包输入法为 D＋锁；开锁表示未锁定，闭锁表示已锁定，警告标记表示暂停。这是工具自己的菜单栏图标，系统输入菜单仍由 macOS 单独显示。首次启动会把当前输入来源设为主要目标，但**不会自动开启锁定**。点击菜单栏图标，选择“主要输入法”，再点击“锁定输入法”。

DMG 中的 App 使用临时签名，尚未经过 Apple Developer ID 公证。其他 Mac 可能出现系统信任提示；需要无此限制的分发版本时，须完成 Developer ID 签名与公证。

## 从源码构建

需要 Xcode Command Line Tools（`xcode-select --install`）。在仓库目录运行：

```bash
./scripts/build_app.sh
open dist/BoardLock.app
```

制作可分享的 DMG：

```bash
./scripts/build_dmg.sh
```

若要测试逻辑，可运行：

```bash
./scripts/run_tests.sh
```

当前测试覆盖 10 组场景、71 个断言。构建脚本会生成并本地签名 `dist/BoardLock.app`。`.build/` 与 `dist/` 是生成文件，不纳入 Git。若不想把 Swift 构建缓存放在仓库目录，可设置 `INPUTSOURCELOCK_BUILD_DIR=/path/to/cache`。

## 使用

- **换目标**：在“选择主要输入法”中选新的输入来源。旧目标会从默认允许列表移除。
- **允许同一输入法的其他来源**：在“管理额外允许的输入法”中手动勾选。适用于把中英等模式暴露为多个系统输入来源的输入法。
- **暂停与恢复**：目标不可用，或系统反复拒绝切换时，菜单栏会显示暂停原因。重新启用目标或手动重新锁定即可恢复。
- **退出**：点击菜单中的“退出 BoardLock”。

默认只允许你选中的那个输入来源 ID。工具不会按 bundle ID 自动把同厂商的来源归为一组：例如系统拼音、双拼、五笔可能同属一个 bundle，但不是同一个锁定目标。

## 工作原理与边界

工具使用 macOS Carbon TIS API 读取、选择输入来源，并监听来源变化通知。发现切离目标后，约 150 ms 后再次确认当前来源，再执行恢复。它不监听键盘按键，不需要辅助功能或输入监控权限。

微信输入法当前版本的可选来源是 `com.tencent.inputmethod.wetype.pinyin`。按来源 ID 锁定不会主动改变它的内部中英文状态。**真实 Shift 切换和打字体验仍需在你的 Mac 上手动验收**。如果某款输入法把英文模式实现为系统 ABC 来源，必须根据实际行为决定是否将该来源加入允许列表。

这种锁定是“切走后恢复”，切换瞬间可能可见。密码框等安全输入场景可能由系统强制使用英文来源；工具限制每秒最多 3 次恢复尝试，连续失败 3 次会暂停，避免循环抢夺输入法。

## 开发记录

方案选择、TIS 枚举结果、代码审核与修复记录在 [开发记录](docs/development.md)。本机输入来源采样在 [TIS 记录](docs/tis_dump.md)，可用 `swift scripts/dump_tis.swift` 在自己的图形登录会话中重新采样。

主要代码位于 `Sources/InputSourceLockCore/`（状态、选择与限流）和 `Sources/InputSourceLockApp/`（菜单栏界面）；测试在 `Tests/InputSourceLockTests/`。

## 分发说明

Release 附带的 DMG 仅包含 arm64 App、Applications 快捷方式和安装说明。源码与构建脚本保留在仓库中，供审查和重新构建。
