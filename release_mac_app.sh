#!/bin/sh

set -eu

APP_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/releases/DARWIN/OpenBOR.app" && pwd)"
CONTENTS="$APP_ROOT/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
LIB_DIR="$CONTENTS/Libraries"
BIN_SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/OpenBOR"
BIN_DST="$MACOS_DIR/OpenBOR-bin"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$LIB_DIR"

cp "$BIN_SRC" "$BIN_DST"
chmod 755 "$BIN_DST"

cp resources/Info.plist "$CONTENTS/Info.plist"
cp resources/PkgInfo "$CONTENTS/PkgInfo"
cp resources/OpenBOR.icns "$RES_DIR/OpenBOR.icns"

cat > "$MACOS_DIR/OpenBOR" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
RES_DIR="$APP_ROOT/Resources"
mkdir -p "$RES_DIR/Paks" "$RES_DIR/Saves" "$RES_DIR/Logs" "$RES_DIR/ScreenShots"
cd "$RES_DIR"
if [ "$#" -gt 0 ]; then
  exec "$SCRIPT_DIR/OpenBOR-bin" "$@"
fi

ACTION="$(osascript <<'OSA'
set menuItems to {"Avvia gioco", "Apri cartella Paks", "Apri cartella Saves", "Guida controlli", "Annulla"}
set selectedItem to choose from list menuItems with title "OpenBOR" with prompt "Scegli un'azione" default items {"Avvia gioco"}
if selectedItem is false then
  return "Annulla"
end if
return item 1 of selectedItem
OSA
)"

case "$ACTION" in
  "Apri cartella Paks")
    open "$RES_DIR/Paks"
    exit 0
    ;;
  "Apri cartella Saves")
    open "$RES_DIR/Saves"
    exit 0
    ;;
  "Guida controlli")
    osascript -e 'display dialog "Rimappatura controlli:\n1. Avvia un gioco.\n2. Premi Start o Invio per mettere in pausa.\n3. Vai su Options.\n4. Apri Control Options.\n5. Seleziona Setup Player 1...\n\nFullscreen:\n- F11\n- oppure Alt+Invio" buttons {"OK"} default button "OK"' >/dev/null 2>&1 || true
    exit 0
    ;;
  "Annulla")
    exit 0
    ;;
esac

set -- Paks/*.pak
if [ "$1" = 'Paks/*.pak' ]; then
  osascript -e 'display alert "OpenBOR" message "Nessun file .pak trovato nella cartella Paks dell''app." as critical buttons {"OK"} default button "OK"' >/dev/null 2>&1 || true
  exit 1
fi

if [ "$#" -eq 1 ]; then
  exec "$SCRIPT_DIR/OpenBOR-bin" "$1"
fi

PAK_LIST=""
for pak in "$@"; do
  name="$(basename "$pak")"
  if [ -z "$PAK_LIST" ]; then
    PAK_LIST="\"$name\""
  else
    PAK_LIST="$PAK_LIST, \"$name\""
  fi
done

CHOICE="$(osascript <<OSA
set pakList to {$PAK_LIST}
set selectedPak to choose from list pakList with title "OpenBOR" with prompt "Scegli il gioco da avviare" default items {(item 1 of pakList)}
if selectedPak is false then
  return ""
end if
return item 1 of selectedPak
OSA
)"

if [ -z "$CHOICE" ]; then
  exit 0
fi

exec "$SCRIPT_DIR/OpenBOR-bin" "Paks/$CHOICE"
EOF
chmod 755 "$MACOS_DIR/OpenBOR"

for lib in \
  /opt/homebrew/opt/sdl2_gfx/lib/libSDL2_gfx-1.0.0.dylib \
  /opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib \
  /opt/homebrew/opt/libvorbis/lib/libvorbisfile.3.dylib \
  /opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib \
  /opt/homebrew/opt/libogg/lib/libogg.0.dylib \
  /opt/homebrew/opt/libvpx/lib/libvpx.11.dylib \
  /opt/homebrew/opt/libpng/lib/libpng16.16.dylib
do
  cp -f "$lib" "$LIB_DIR/"
  chmod 755 "$LIB_DIR/$(basename "$lib")"
done

for lib in "$LIB_DIR"/*.dylib
do
  install_name_tool -id "@executable_path/../Libraries/$(basename "$lib")" "$lib"
done

install_name_tool \
  -change /opt/homebrew/opt/sdl2_gfx/lib/libSDL2_gfx-1.0.0.dylib @executable_path/../Libraries/libSDL2_gfx-1.0.0.dylib \
  -change /opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib @executable_path/../Libraries/libSDL2-2.0.0.dylib \
  -change /opt/homebrew/opt/libvorbis/lib/libvorbisfile.3.dylib @executable_path/../Libraries/libvorbisfile.3.dylib \
  -change /opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib @executable_path/../Libraries/libvorbis.0.dylib \
  -change /opt/homebrew/opt/libogg/lib/libogg.0.dylib @executable_path/../Libraries/libogg.0.dylib \
  -change /opt/homebrew/opt/libvpx/lib/libvpx.11.dylib @executable_path/../Libraries/libvpx.11.dylib \
  -change /opt/homebrew/opt/libpng/lib/libpng16.16.dylib @executable_path/../Libraries/libpng16.16.dylib \
  "$BIN_DST"

install_name_tool \
  -change /opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib @executable_path/../Libraries/libSDL2-2.0.0.dylib \
  "$LIB_DIR/libSDL2_gfx-1.0.0.dylib"

install_name_tool \
  -change /opt/homebrew/opt/libogg/lib/libogg.0.dylib @executable_path/../Libraries/libogg.0.dylib \
  -change /opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib @executable_path/../Libraries/libvorbis.0.dylib \
  -change /opt/homebrew/Cellar/libvorbis/1.3.7/lib/libvorbis.0.dylib @executable_path/../Libraries/libvorbis.0.dylib \
  "$LIB_DIR/libvorbisfile.3.dylib"

install_name_tool \
  -change /opt/homebrew/opt/libogg/lib/libogg.0.dylib @executable_path/../Libraries/libogg.0.dylib \
  "$LIB_DIR/libvorbis.0.dylib"

codesign --force --deep --sign - "$APP_ROOT" >/dev/null 2>&1 || true

echo "Created macOS app bundle at: $APP_ROOT"
