#!/bin/bash
# Baut ein .rbz — so, wie Raphi Plugins kennt.
#
# In seinem Dokumente-Ordner liegen Dutzende `*_signed.rbz`. Doppelklick, SketchUp
# installiert. Das ist seine Sprache; ein Shell-Skript ist es nicht.
# (Ein .rbz IST nur ein ZIP mit der Loader-Datei und dem Ordner daneben.)
#
#   ./paket.sh            -> ~/Desktop/malmops-<datum>.rbz
#   ./paket.sh /ziel/pfad
#
# 🔴 Unsigniert. Steht in SketchUp unter Einstellungen → Erweiterungen die
# Ladepolitik auf „Nur signierte", muss er sie einmal auf „Unbekannte zulassen"
# stellen — sonst installiert er es und nichts passiert, ohne Fehlermeldung.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIEL="${1:-$HOME/Desktop}"
NAME="malmops-$(date +%Y%m%d).rbz"
AUS="$ZIEL/$NAME"

BAU="$(mktemp -d)"
trap 'rm -rf "$BAU"' EXIT

cp "$REPO/mops_scetchup.rb" "$BAU/"
cp -R "$REPO/mops_scetchup" "$BAU/"

# Nichts mitschleppen, was nicht ins Paket gehört.
find "$BAU" -name '*.backup_*' -delete
find "$BAU" -name '.DS_Store' -delete

rm -f "$AUS"
(cd "$BAU" && zip -qr "$AUS" mops_scetchup.rb mops_scetchup)

echo "✓ $AUS"
echo "  $(du -h "$AUS" | cut -f1)"
echo
echo "So installiert Raphi es:"
echo "  SketchUp → Erweiterungen → Erweiterungs-Manager → 'Erweiterung installieren'"
echo "  → diese Datei wählen → SketchUp neu starten"
echo
echo "Dann noch ~/.mops-sketchup.json anlegen (URL + Schlüssel), sonst bleibt"
echo "das Plugin im FAKE-Modus bzw. die Box sagt 401."
