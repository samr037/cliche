#!/bin/sh
# Publie une version : scripts/release.sh 0.3.0
#  1. vérifie l'arbre (main, propre, à jour, tests et traductions verts) ;
#  2. met la version dans Resources/Info.plist ;
#  3. transforme « ## [Unreleased] » de CHANGELOG.md en « ## [0.3.0] - date » ;
#  4. commit, tag v0.3.0, push. La CI (release.yml) construit et publie le DMG.
set -e
cd "$(dirname "$0")/.."
V="$1"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "usage: scripts/release.sh X.Y.Z"; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Pas sur main."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Modifications non commitées."; exit 1; }
git fetch -q origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main n'est pas à jour avec origin/main."; exit 1; }
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && { echo "Le tag v$V existe déjà."; exit 1; }
OLD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
# Version strictement croissante.
[ "$(printf '%s\n%s\n' "$OLD" "$V" | sort -V | tail -1)" = "$V" ] && [ "$OLD" != "$V" ] || { echo "$V doit être > $OLD."; exit 1; }
# Le changelog doit décrire quelque chose.
awk '/^## \[Unreleased\]/{p=1; next} /^## \[/{p=0} p && /[^[:space:]]/' CHANGELOG.md | grep -q . \
  || { echo "CHANGELOG.md : la section [Unreleased] est vide."; exit 1; }

python3 scripts/l10n.py check
scripts/test.sh >/dev/null

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Resources/Info.plist
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" Resources/Info.plist
DATE=$(date +%Y-%m-%d)
python3 - "$V" "$DATE" <<'PY'
import sys
v, d = sys.argv[1], sys.argv[2]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
s = s.replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{v}] - {d}\n", 1)
open(p, "w", encoding="utf-8").write(s)
PY
git add Resources/Info.plist CHANGELOG.md
git commit -qm "Version $V"
git tag -a "v$V" -m "Cliché $V"
git push -q origin main "v$V"
echo "v$V poussé. Suivi : gh run watch -R samr037/cliche \$(gh run list -R samr037/cliche --workflow release.yml -L1 --json databaseId -q '.[0].databaseId')"
