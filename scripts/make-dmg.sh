#!/bin/sh
# Emballe Cliché.app dans un DMG glisser-déposer, avec fond et icônes placées :
#   make-dmg.sh <Cliché.app> <sortie.dmg>
set -e
APP="$1"
OUT="$2"
[ -d "$APP" ] && [ -n "$OUT" ] || { echo "usage: make-dmg.sh <Cliché.app> <sortie.dmg>"; exit 1; }
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Cliché.app"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/Read me.txt"
mkdir "$STAGE/.background"
cp Resources/brand/dmg-background.png "$STAGE/.background/bg.png"

# Image lecture-écriture pour placer les icônes via le Finder, puis conversion compressée.
RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname "Cliché" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
MNT="/Volumes/Cliché"
# Mise en page Finder (ignorée sans session graphique, ex. certains runners : le DMG reste valide).
osascript <<OSA || echo "Mise en page Finder indisponible, DMG sans fond"
tell application "Finder"
  tell disk "Cliché"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 640}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:bg.png"
    set position of item "Cliché.app" of container window to {170, 190}
    set position of item "Applications" of container window to {490, 190}
    set position of item "Read me.txt" of container window to {330, 330}
    close
  end tell
end tell
OSA
sync
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -rf "$STAGE" "$(dirname "$RW")"
echo "DMG : $OUT"
