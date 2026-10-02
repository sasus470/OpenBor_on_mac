#!/bin/zsh
set -euo pipefail

ROOT="/Users/salvatorecuccoro/Documents/New project"
PRODUCT_NAME="OpenBORMacV2"
BUILD_DIR="$ROOT/.build"
OUTPUT_DIR="$ROOT/build/v2"
APP_DIR="$OUTPUT_DIR/OpenBOR Mac V2.app"
BIN_PATH="$BUILD_DIR/release/$PRODUCT_NAME"
FRONTEND_APP_DIR="$ROOT/build/frontend/OpenBOR Frontend Launcher.app"
FRONTEND_RESOURCES_DIR="$FRONTEND_APP_DIR/Contents/Resources"
ENGINE_SOURCE_APP="$FRONTEND_RESOURCES_DIR/Engine/OpenBOR.app"
SEED_PAKS_SOURCE_DIR="$FRONTEND_RESOURCES_DIR/SeedPaks"
V2_RESOURCES_DIR="$APP_DIR/Contents/Resources"
V2_ENGINE_DIR="$V2_RESOURCES_DIR/Engine"
V2_SEED_PAKS_DIR="$V2_RESOURCES_DIR/SeedPaks"

mkdir -p "$OUTPUT_DIR"

"$ROOT/build_openbor_frontend.sh"

swift build -c release --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$ROOT/OpenBORMacV2/Info.plist" "$APP_DIR/Contents/Info.plist"

mkdir -p "$V2_ENGINE_DIR" "$V2_SEED_PAKS_DIR"

if [ -d "$ENGINE_SOURCE_APP" ]; then
  cp -R "$ENGINE_SOURCE_APP" "$V2_ENGINE_DIR/"
fi

if [ -d "$SEED_PAKS_SOURCE_DIR" ]; then
  find "$SEED_PAKS_SOURCE_DIR" -maxdepth 1 -type f -name '*.pak' -print0 | \
    xargs -0 -I{} cp -f "{}" "$V2_SEED_PAKS_DIR/"
fi

echo "Built V2 app at: $APP_DIR"
