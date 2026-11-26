#!/usr/bin/env bash
# 构建未签名 iOS IPA（本地 macOS 与 GitHub Actions 通用）。
#
# 用法：
#   bash scripts/build-ipa.sh
#   SCHEME=MyApp bash scripts/build-ipa.sh
#
# 产物：
#   dist/Ledger-unsigned.ipa
#
# 工程由 project.yml 经 XcodeGen 生成，不手写 .xcodeproj。
# 这里刻意不做任何签名，IPA 由你在设备侧用 Sideloadly / SideStore 重签。

set -euo pipefail

PROJECT="${PROJECT:-Ledger.xcodeproj}"
SCHEME="${SCHEME:-Ledger}"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="${BUILD_DIR:-build}"
OUT_DIR="${OUT_DIR:-dist}"

echo "==> 目标: $SCHEME ($CONFIG)"

# 没有 .xcodeproj 时，用 project.yml 现场生成。
if [ ! -d "$PROJECT" ]; then
  if [ -f project.yml ]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
      echo "错误：缺少 xcodegen。macOS 上执行：brew install xcodegen" >&2
      exit 1
    fi
    echo "==> 未找到 $PROJECT，使用 project.yml 生成"
    xcodegen generate --spec project.yml
  else
    echo "错误：既没有 $PROJECT 也没有 project.yml" >&2
    exit 1
  fi
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# 版本号可由环境变量注入（CI 用构建序号），保证每次出包版本不同
VERSION_ARGS=""
if [ -n "${MARKETING_VERSION:-}" ]; then
  VERSION_ARGS="$VERSION_ARGS MARKETING_VERSION=$MARKETING_VERSION"
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
  VERSION_ARGS="$VERSION_ARGS CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION"
fi
if [ -n "$VERSION_ARGS" ]; then
  echo "==> 版本参数:$VERSION_ARGS"
fi

# 注意：不加 -allowProvisioningUpdates，也不配 Development Team。
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  $VERSION_ARGS \
  build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "错误：找不到构建产物 $APP_PATH" >&2
  echo "已构建出的内容：" >&2
  ls -la "$BUILD_DIR/Build/Products" 2>/dev/null || true
  exit 1
fi

mkdir -p "$OUT_DIR/Payload"
cp -R "$APP_PATH" "$OUT_DIR/Payload/"

# 确保 IPA 是纯净未签名的
rm -rf "$OUT_DIR/Payload/$SCHEME.app/_CodeSignature" 2>/dev/null || true
rm -f  "$OUT_DIR/Payload/$SCHEME.app/embedded.mobileprovision" 2>/dev/null || true

# ---------------------------------------------------------------
# 兜底：把 App 图标 PNG 同时以传统文件名放一份到 App 根目录。
# 重签工具/系统图标缓存只认这些 loose png 时，可以避免桌面图标空白。
# 资产目录里的高清版本仍然在 Assets.car 里，两套并存不冲突。
# ---------------------------------------------------------------
APP_ROOT="$OUT_DIR/Payload/$SCHEME.app"
ICONS_DIR="Ledger/Resources/Assets.xcassets"
copy_icon() {
  if [ -f "$1" ]; then
    cp "$1" "$APP_ROOT/$2"
  fi
}

for prefix in AppIcon AppIconMinimal AppIconCoin AppIconChart; do
  # iPhone 各尺寸：CFBundleIconFiles 基名 + 尺寸 + 倍数
  for size in 20x20 29x29 40x40 60x60; do
    for scale in 2x 3x; do
      copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-iphone-${size}@${scale}.png" "${prefix}${size}@${scale}.png"
    done
  done
  # iPad 各尺寸
  for size in 20x20 29x29 40x40 76x76; do
    for scale in 1x 2x; do
      copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-ipad-${size}@${scale}.png" "${prefix}${size}@${scale}~ipad.png"
    done
  done
  copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-ipad-83_5x83_5@2x.png" "${prefix}83.5x83.5@2x~ipad.png"
  # 备用命名：CFBundleAlternateIcons 里基名就是 AppIconMinimal，系统会在后面直接补 @2x/@3x
  copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-iphone-60x60@2x.png" "${prefix}@2x.png"
  copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-iphone-60x60@3x.png" "${prefix}@3x.png"
  copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-iphone-60x60@2x.png" "${prefix}60x60@2x.png"
  copy_icon "$ICONS_DIR/$prefix.appiconset/${prefix}-iphone-60x60@3x.png" "${prefix}60x60@3x.png"
done

# 最高优先级：CFBundleIconFiles 的合法入口（老系统/重签工具兼容）
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFiles" "$APP_ROOT/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles array" "$APP_ROOT/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:0 string AppIcon60x60" "$APP_ROOT/Info.plist" >/dev/null 2>&1 || true

(
  cd "$OUT_DIR"
  zip -qry "$SCHEME-unsigned.ipa" Payload
)

echo "==> 完成：$OUT_DIR/$SCHEME-unsigned.ipa"
ls -lh "$OUT_DIR/$SCHEME-unsigned.ipa"
