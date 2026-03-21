#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENGINE_DIR="$ROOT_DIR/openbor-src/engine"
FRONTEND_DIR="$ROOT_DIR/OpenBORFrontend"
BUILD_DIR="$ROOT_DIR/build/frontend"
APP_NAME="OpenBOR Frontend Launcher.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENGINE_APP_DIR="$RESOURCES_DIR/Engine/OpenBOR.app"
SEED_PAKS_DIR="$RESOURCES_DIR/SeedPaks"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SEED_PAKS_DIR"

(cd "$ENGINE_DIR" && . ./version.sh 0 >/dev/null && make BUILD_DARWIN=1 >/dev/null && ./release_mac_app.sh >/dev/null)

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SEED_PAKS_DIR" "$RESOURCES_DIR/Engine"

xcrun swiftc \
  -target arm64-apple-macos13.0 \
  -O \
  -module-name OpenBORFrontend \
  -framework SwiftUI \
  -framework AppKit \
  -lsqlite3 \
  "$FRONTEND_DIR/AppModel.swift" \
  "$FRONTEND_DIR/ContentView.swift" \
  "$FRONTEND_DIR/OpenBORFrontendApp.swift" \
  -o "$MACOS_DIR/OpenBORFrontend"

chmod 755 "$MACOS_DIR/OpenBORFrontend"
cp "$FRONTEND_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ENGINE_DIR/resources/OpenBOR.icns" "$RESOURCES_DIR/OpenBOR.icns"
cp -R "$ENGINE_DIR/releases/DARWIN/OpenBOR.app" "$ENGINE_APP_DIR"

mkdir -p "$ENGINE_APP_DIR/Contents/Resources/Paks"
find "$ENGINE_DIR/releases/DARWIN/OpenBOR.app/Contents/Resources/Paks" -maxdepth 1 -type f -name '*.pak' -print0 | \
  xargs -0 -I{} cp -f "{}" "$SEED_PAKS_DIR/"

cat > "$MACOS_DIR/openbor-launch" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
exec "$SCRIPT_DIR/OpenBORFrontend" --launch "$@"
EOF
chmod 755 "$MACOS_DIR/openbor-launch"

find "$ENGINE_APP_DIR/Contents" -type f \( -name '*.dylib' -o -name 'OpenBOR-bin' \) -print0 | \
  xargs -0 -I{} codesign --force --sign - "{}" >/dev/null 2>&1 || true

xattr -cr "$APP_DIR" || true

echo "Built frontend app at: $APP_DIR"
