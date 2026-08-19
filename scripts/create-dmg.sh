#!/bin/bash

# LockInput DMG 打包脚本
# 用法: ./scripts/create-dmg.sh

set -e

APP_NAME="LockInput"
DMG_NAME="LockInput"
VERSION="1.1"
BUILD_DIR="build/Build/Products/Release"
APP_PATH="$BUILD_DIR/lockinput.app"
DMG_PATH="$DMG_NAME-$VERSION.dmg"
TEMP_DMG="temp_$DMG_NAME.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

echo "📦 Creating DMG for $APP_NAME..."

# 检查 app 是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH not found!"
    echo "Please build the app first:"
    echo "  xcodebuild -project lockinput.xcodeproj -scheme lockinput -configuration Release -derivedDataPath build clean build"
    exit 1
fi

# 清理旧文件
rm -f "$DMG_PATH" "$TEMP_DMG"
rm -rf dmg_temp

# 创建临时目录
mkdir -p dmg_temp
cp -R "$APP_PATH" dmg_temp/

# 创建 Applications 符号链接
ln -s /Applications dmg_temp/Applications

# 创建临时 DMG
echo "📀 Creating temporary DMG..."
hdiutil create -srcfolder dmg_temp -volname "$VOLUME_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG"

# 挂载临时 DMG
echo "💿 Mounting DMG..."
DEVICE=$(hdiutil attach -readwrite -noverify "$TEMP_DMG" | grep "/Volumes/$VOLUME_NAME" | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# 等待挂载完成
sleep 2

# 设置窗口样式 (使用 AppleScript)
echo "🎨 Setting window style..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 1000, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "lockinput.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# 同步并卸载
sync
hdiutil detach "$DEVICE"

# 转换为压缩 DMG
echo "🗜️ Compressing DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

# 清理临时文件
rm -f "$TEMP_DMG"
rm -rf dmg_temp

echo ""
echo "✅ DMG created successfully: $DMG_PATH"
echo "📊 Size: $(du -h "$DMG_PATH" | cut -f1)"
