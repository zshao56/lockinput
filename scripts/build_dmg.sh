#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/dist/BoardLock.app"
DMG_PATH="$PROJECT_DIR/dist/BoardLock-v0.1.3-arm64.dmg"

"$SCRIPT_DIR/build_app.sh"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boardlock-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_BUNDLE" "$STAGING_DIR/BoardLock.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/安装说明.txt" <<'NOTES'
BoardLock

1. 如果已安装旧版 InputSourceLock.app，请先退出并从 Applications 中移走，避免两个版本同时运行。
2. 将 BoardLock.app 拖入 Applications 文件夹。
3. 启动后在菜单栏点击“输入法首字母＋锁”图标，选择主要输入法，再开启锁定。
4. 此包仅支持 Apple Silicon（M 芯片），需要 macOS 13 或更新版本。

这是临时签名、未经 Apple 公证的社区构建。若系统阻止打开，请从 GitHub 源码自行构建，或等待经过 Developer ID 签名与公证的正式版本。
NOTES

rm -f "$DMG_PATH"
diskutil image create from --format UDZO --volumeName BoardLock "$STAGING_DIR" "$DMG_PATH"
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
echo "==> DMG ready: $DMG_PATH"
