#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENGINE_DIR="$ROOT_DIR/openbor-src/engine"
FRONTEND_DIR="$ROOT_DIR/OpenBORFrontend"
BUILD_DIR="$ROOT_DIR/build/frontend"
FINAL_DIR="$ROOT_DIR/build/final"
APP_BASE_NAME="OpenBOR Frontend Launcher"
APP_NAME="$APP_BASE_NAME.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENGINE_APP_DIR="$RESOURCES_DIR/Engine/OpenBOR.app"
SEED_PAKS_DIR="$RESOURCES_DIR/SeedPaks"
FRONTEND_ICON_ICNS="$RESOURCES_DIR/OpenBORFrontend.icns"
FRONTEND_ICON_SWIFT="$FRONTEND_DIR/generate_frontend_icon.swift"
BUILD_STAMP="${BUILD_STAMP:-$(date +%Y%m%d-%H%M)}"
FINAL_APP_DIR="$FINAL_DIR/$APP_NAME"
VERSIONED_APP_DIR="$FINAL_DIR/$APP_BASE_NAME $BUILD_STAMP.app"
VERSIONED_ZIP_PATH="$FINAL_DIR/$APP_BASE_NAME $BUILD_STAMP.zip"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SEED_PAKS_DIR" "$FINAL_DIR"

(cd "$ENGINE_DIR" && \
  if [ -d .git ] || [ -d ../.git ]; then
    . ./version.sh 0 >/dev/null
  else
    printf '0\n0000000\n' | bash ./version.sh 0 >/dev/null
  fi && \
  make BUILD_DARWIN=1 >/dev/null && \
  ./release_mac_app.sh >/dev/null)

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SEED_PAKS_DIR" "$RESOURCES_DIR/Engine"

xcrun swiftc \
  -target arm64-apple-macos14.0 \
  -O \
  -module-name OpenBORFrontend \
  -framework SwiftUI \
  -framework WebKit \
  -framework AppKit \
  -framework GameController \
  -framework Metal \
  -framework MetalKit \
  -framework OpenGL \
  -framework IOSurface \
  -framework QuartzCore \
  -lsqlite3 \
  "$FRONTEND_DIR/AppModel.swift" \
  "$FRONTEND_DIR/ContentView.swift" \
  "$FRONTEND_DIR/OpenBORFrontendApp.swift" \
  "$FRONTEND_DIR/LauncherSessionView.swift" \
  "$FRONTEND_DIR/ArcadeLauncherStyle.swift" \
  "$FRONTEND_DIR/CoverBrowserView.swift" \
  "$ROOT_DIR"/OpenBORMacV2/Host/*.swift \
  "$ROOT_DIR"/OpenBORMacV2/Renderer/*.swift \
  "$ROOT_DIR"/OpenBORMacV2/EngineBridge/*.swift \
  -o "$MACOS_DIR/OpenBORFrontend"

chmod 755 "$MACOS_DIR/OpenBORFrontend"
cp "$FRONTEND_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

ICON_WORKDIR="$(mktemp -d)"
ICONSET_DIR="$ICON_WORKDIR/OpenBORFrontend.iconset"
RENDERED_ICON="$ICON_WORKDIR/OpenBORFrontend.png"
mkdir -p "$ICONSET_DIR"
xcrun swift "$FRONTEND_ICON_SWIFT" "$RENDERED_ICON" >/dev/null

sips -z 16 16     "$RENDERED_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$RENDERED_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$RENDERED_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$RENDERED_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$RENDERED_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$RENDERED_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$RENDERED_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$RENDERED_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$RENDERED_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$RENDERED_ICON" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$FRONTEND_ICON_ICNS"
rm -rf "$ICON_WORKDIR"

cp -R "$ENGINE_DIR/releases/DARWIN/OpenBOR.app" "$ENGINE_APP_DIR"

mkdir -p "$ENGINE_APP_DIR/Contents/Resources/Paks"
SOURCE_PAKS_DIR="$ENGINE_DIR/releases/DARWIN/OpenBOR.app/Contents/Resources/Paks"
if [ -d "$SOURCE_PAKS_DIR" ]; then
  find "$SOURCE_PAKS_DIR" -maxdepth 1 -type f -name '*.pak' -print0 | \
    xargs -0 -I{} cp -f "{}" "$SEED_PAKS_DIR/"
fi

cat > "$MACOS_DIR/openbor-launch" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
if [ "$#" -eq 1 ] && [ -f "$1" ]; then
  exec "$SCRIPT_DIR/OpenBORFrontend" --pak "$1"
fi
exec "$SCRIPT_DIR/OpenBORFrontend" "$@"
EOF
chmod 755 "$MACOS_DIR/openbor-launch"

find "$ENGINE_APP_DIR/Contents" -type f \( -name '*.dylib' -o -name 'OpenBOR-bin' \) -print0 | \
  xargs -0 -I{} codesign --force --sign - "{}" >/dev/null 2>&1 || true

xattr -cr "$APP_DIR" || true

rm -rf "$FINAL_APP_DIR" "$VERSIONED_APP_DIR" "$VERSIONED_ZIP_PATH"
cp -R "$APP_DIR" "$FINAL_APP_DIR"
cp -R "$APP_DIR" "$VERSIONED_APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$VERSIONED_APP_DIR" "$VERSIONED_ZIP_PATH"

echo "Built frontend app at: $APP_DIR"
echo "Updated stable final app at: $FINAL_APP_DIR"
echo "Created versioned final app at: $VERSIONED_APP_DIR"
echo "Created versioned final zip at: $VERSIONED_ZIP_PATH"
