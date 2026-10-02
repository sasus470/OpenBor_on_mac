#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENGINE_DIR="$ROOT_DIR/openbor-src/engine"
REFERENCE_DIR="$ROOT_DIR/build/reference"
REFERENCE_APP="$REFERENCE_DIR/OpenBOR Reference 4.0.app"
REFERENCE_PAKS_DIR="$REFERENCE_APP/Contents/Resources/Paks"
PRIMARY_PAK_SOURCE="$HOME/Library/Application Support/OpenBORMacV2/Paks"
FALLBACK_PAK_SOURCE="$ROOT_DIR/build/frontend/OpenBOR Frontend Launcher.app/Contents/Resources/SeedPaks"

mkdir -p "$REFERENCE_DIR"

(cd "$ENGINE_DIR" && \
  if [ -d .git ] || [ -d ../.git ]; then
    . ./version.sh 0 >/dev/null
  else
    printf '0\n0000000\n' | bash ./version.sh 0 >/dev/null
  fi && \
  make BUILD_DARWIN=1 >/dev/null && \
  ./release_mac_app.sh >/dev/null)

rm -rf "$REFERENCE_APP"
cp -R "$ENGINE_DIR/releases/DARWIN/OpenBOR.app" "$REFERENCE_APP"
mkdir -p "$REFERENCE_PAKS_DIR"

if [ -d "$PRIMARY_PAK_SOURCE" ]; then
  find "$PRIMARY_PAK_SOURCE" -maxdepth 1 -type f -name '*.pak' -print0 | \
    xargs -0 -I{} cp -f "{}" "$REFERENCE_PAKS_DIR/"
fi

if [ ! "$(find "$REFERENCE_PAKS_DIR" -maxdepth 1 -type f -name '*.pak' -print -quit)" ] && [ -d "$FALLBACK_PAK_SOURCE" ]; then
  find "$FALLBACK_PAK_SOURCE" -maxdepth 1 -type f -name '*.pak' -print0 | \
    xargs -0 -I{} cp -f "{}" "$REFERENCE_PAKS_DIR/"
fi

cat > "$REFERENCE_APP/Contents/MacOS/OpenBOR" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
BUNDLED_RES_DIR="$APP_ROOT/Resources"
DATA_ROOT="$HOME/Library/Application Support/OpenBOR Reference 4.0"
RUNTIME_DIR="$DATA_ROOT/Runtime"
mkdir -p "$DATA_ROOT/Saves" "$DATA_ROOT/Logs" "$DATA_ROOT/ScreenShots" "$RUNTIME_DIR"
ln -sfn "$BUNDLED_RES_DIR/Paks" "$RUNTIME_DIR/Paks"
ln -sfn "$DATA_ROOT/Saves" "$RUNTIME_DIR/Saves"
ln -sfn "$DATA_ROOT/Logs" "$RUNTIME_DIR/Logs"
ln -sfn "$DATA_ROOT/ScreenShots" "$RUNTIME_DIR/ScreenShots"
cd "$RUNTIME_DIR"
if [ "$#" -gt 0 ]; then
  exec "$SCRIPT_DIR/OpenBOR-bin" "$@"
fi

ACTION="$(osascript <<'OSA'
set menuItems to {"Avvia gioco", "Apri cartella Paks", "Apri cartella Saves", "Guida controlli", "Annulla"}
set selectedItem to choose from list menuItems with title "OpenBOR Reference" with prompt "Scegli un'azione" default items {"Avvia gioco"}
if selectedItem is false then
  return "Annulla"
end if
return item 1 of selectedItem
OSA
)"

case "$ACTION" in
  "Apri cartella Paks")
    open "$BUNDLED_RES_DIR/Paks"
    exit 0
    ;;
  "Apri cartella Saves")
    open "$DATA_ROOT/Saves"
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
  osascript -e 'display alert "OpenBOR Reference" message "Nessun file .pak trovato nella cartella Paks dell''app." as critical buttons {"OK"} default button "OK"' >/dev/null 2>&1 || true
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
set selectedPak to choose from list pakList with title "OpenBOR Reference" with prompt "Scegli il gioco da avviare" default items {(item 1 of pakList)}
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
chmod 755 "$REFERENCE_APP/Contents/MacOS/OpenBOR"

xattr -cr "$REFERENCE_APP" || true
find "$REFERENCE_APP/Contents" -type f \( -name '*.dylib' -o -name 'OpenBOR-bin' \) -print0 | \
  xargs -0 -I{} codesign --force --sign - "{}" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$REFERENCE_APP" >/dev/null 2>&1 || true

echo "Built reference app at: $REFERENCE_APP"
