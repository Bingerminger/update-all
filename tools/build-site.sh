#!/usr/bin/env bash
# Projektseite für GitHub Pages bauen: site/ + Bilder aus docs/ und .github/ → <ziel>
# (Standard dist/site). Die Version kommt aus update-all.sh. Mit --check wird nur geprüft,
# ob jedes Bild, das die Seite einbindet, vorhanden ist.
# Läuft auf macOS und auf den Ubuntu-Runnern (bash, sed, cp — nichts weiter).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
check=0; out="$root/dist/site"
for a in "$@"; do case $a in --check) check=1 ;; *) out=$a ;; esac; done

declare -a assets=(docs/demo.gif docs/screenshots/wide.png docs/screenshots/done.png
                   docs/screenshots/ipad.png docs/screenshots/iphone.png .github/social-preview.png)
missing=0
for f in "${assets[@]}"; do [[ -f $root/$f ]] || { echo "fehlt: $f" >&2; missing=1; }; done
for ref in $(grep -o 'assets/[A-Za-z0-9._-]*' "$root/site/index.html" | sort -u); do
  n=${ref#assets/}; found=0
  for f in "${assets[@]}"; do [[ ${f##*/} == "$n" ]] && found=1; done
  (( found )) || { echo "index.html bindet $ref ein, das Build-Skript kennt es nicht" >&2; missing=1; }
done
(( missing )) && exit 1
(( check )) && { echo "Projektseite: alle Bilder vorhanden"; exit 0; }

# SITE_VERSION übersteuert (pages.yml: Version des neuesten Releases, die Seite selbst kommt aus main)
version=${SITE_VERSION:-$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$root/update-all.sh")}
[[ -n $version ]] || { echo "VERSION nicht gefunden" >&2; exit 1; }
rm -rf "$out"; mkdir -p "$out/assets"
cp "$root"/site/* "$out/"
for f in "${assets[@]}"; do cp "$root/$f" "$out/assets/"; done
sed "s/{{VERSION}}/$version/g" "$root/site/index.html" > "$out/index.html"
touch "$out/.nojekyll"
echo "Projektseite $version → $out ($(du -sh "$out" | cut -f1))"
