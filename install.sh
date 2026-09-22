#!/bin/bash
# Malmops in SketchUp einhängen — ein Befehl.
#
# Hängt das Plugin per Symlink in den SketchUp-Plugins-Ordner. Symlink und nicht
# Kopie: dann zieht ein `git pull` die Updates gleich mit, und niemand fragt sich
# später, welche von zwei Fassungen gerade läuft.
#
#   ./install.sh              zeigt nur, was es täte
#   ./install.sh --wirklich   macht es
#
# Danach muss SketchUp EINMAL neu gestartet werden — Extensions werden nur beim
# Start geladen. Läuft SketchUp gerade, passiert also erst mal gar nichts; das
# ist Absicht und stört niemanden bei der Arbeit.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KONFIG="$HOME/.mops-sketchup.json"
ECHT="${1:-}"

# Neueste installierte SketchUp-Version nehmen, nicht raten.
PLUG=""
for d in "$HOME/Library/Application Support/SketchUp "*; do
  [ -d "$d/SketchUp/Plugins" ] && PLUG="$d/SketchUp/Plugins"
done

if [ -z "$PLUG" ]; then
  echo "Kein SketchUp-Plugins-Ordner gefunden."
  echo "Gesucht unter: ~/Library/Application Support/SketchUp <Version>/SketchUp/Plugins"
  exit 1
fi

echo "Repo:            $REPO"
echo "Plugins-Ordner:  $PLUG"
echo "Konfig:          $KONFIG"
echo

if pgrep -x SketchUp >/dev/null 2>&1; then
  echo "ℹ  SketchUp läuft gerade. Das Einhängen stört nicht — wirksam wird es"
  echo "   aber erst beim nächsten Start."
  echo
fi

if [ "$ECHT" != "--wirklich" ]; then
  echo "TROCKENLAUF — es wird nichts verändert. Zum echten Einhängen:"
  echo "    $0 --wirklich"
  exit 0
fi

ln -sfn "$REPO/mops_scetchup.rb" "$PLUG/mops_scetchup.rb"
ln -sfn "$REPO/mops_scetchup"    "$PLUG/mops_scetchup"
echo "✓ eingehängt"

if [ ! -f "$KONFIG" ]; then
  cat > "$KONFIG" <<'JSON'
{
  "url": "http://mops-box:8000",
  "schluessel": "HIER-DEN-SCHLUESSEL-EINTRAGEN",
  "wer": "Raphael"
}
JSON
  chmod 600 "$KONFIG"
  echo "✓ Konfig angelegt: $KONFIG"
  echo "  🔴 Der Schlüssel fehlt noch. Ohne ihn sagt die Box 401."
  echo "     Er steht auf der Box in der .env als SKETCHUP_SCHLUESSEL."
else
  echo "✓ Konfig war schon da (bleibt unangetastet)"
fi

echo
echo "Jetzt SketchUp einmal neu starten."
echo "Dann: ein Bauteil markieren → Extensions → 'Mops fragen'."
