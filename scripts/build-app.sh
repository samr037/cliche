#!/bin/sh
# Construit Cliché.app.
#   CLICHE_BUILD  dossier de build SwiftPM (hors de ~/Claude : "build.db disk I/O error" sinon)
#   CLICHE_APP    app produite (défaut ~/Applications/Cliché.app)
#   CLICHE_SIGN   identité de signature stable (l'autorisation d'enregistrement d'écran y est rattachée) ; "-" = ad hoc
#   CLICHE_VERSION  version affichée (CFBundleShortVersionString)
set -e
cd "$(dirname "$0")/.."
BUILD="${CLICHE_BUILD:-/tmp/cliche-build}"
APP="${CLICHE_APP:-$HOME/Applications/Cliché.app}"
IDENTITY="${CLICHE_SIGN:-WisprLocal Dev}"
swift build -c release --product Cliche --scratch-path "$BUILD"
BIN="$(swift build -c release --product Cliche --scratch-path "$BUILD" --show-bin-path)/Cliche"
rm -rf "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -n "$CLICHE_VERSION" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CLICHE_VERSION" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Cliche"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[ -f LICENSE ] && cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
codesign --force --sign "$IDENTITY" --identifier io.github.samr037.cliche "$APP"
codesign --verify --strict "$APP"
echo "Construit : $APP"
