# mops-scetchup — der Malmops für SketchUp

Eine SketchUp-Extension mit einem Mops-Knopf: markiertes Bauteil an den Mops schicken.
Der Mops sagt, **was er an Raphaels Namenskonvention gelesen hat** (Geschoss, Bauteilart,
Dicke, Güte, Kostengruppe), schreibt es als Attribut ans Bauteil — und stellt
**höchstens eine Frage** zurück, die man wegklicken kann.

> Andreas am 22.09.2026: „es muss aussehen als ob das plugin mit ihm spielt. jeden Tag
> oder so eine einzige frage, die er auch wegklicken kann."

Raphi zeichnet ohnehin. Also holt der Mops seinen Beitrag dort ab, wo er sowieso ist,
statt ihn zu einem Prozess zu holen. Was er antwortet, trägt **seinen Namen**:
„geprüft von Raphael" steht später bei dem, der den Arbeitsschritt draussen liest.

**Stand: Spike, aber der ganze Weg läuft.** `FAKE = true` antwortet lokal, damit die
Kette ohne Box testbar ist. Der echte Weg (`/sketchup/match` + `/sketchup/antwort`) ist
in `mops-api` gebaut und über HTTP durchgespielt — siehe `docs/box-endpoint.md`.

🔴 **Der Mops erfindet keinen Preis.** Im Backend gibt es (Stand 22.09.) keinen
STLB-Matcher und keine Aufwandswerte — die liegen im iOS-Client. Also kommen
`baustein` und `preis` als `null` zurück. Eine plausible Zahl wäre schlimmer als keine.

## Installieren

**Für Raphi — so, wie er Plugins kennt:**

```bash
./paket.sh                 # baut ~/Desktop/malmops-<datum>.rbz
```

Die `.rbz` doppelklicken bzw. in SketchUp über *Erweiterungen → Erweiterungs-Manager →
Erweiterung installieren* wählen, dann SketchUp neu starten.
🔴 Unsigniert: steht die Ladepolitik auf „nur signierte Erweiterungen", installiert er
es und **nichts passiert, ohne Fehlermeldung**. Einmal auf „unbekannte zulassen" stellen.

**Für Entwickler — mit Symlink, dann zieht `git pull` die Updates mit:**

```bash
./install.sh               # Trockenlauf, zeigt nur was passiert
./install.sh --wirklich
```

## Zugang (nicht im Repo)

`~/.mops-sketchup.json`, Rechte 600:

```json
{ "url": "http://mops-box:8080", "schluessel": "...", "wer": "Raphael" }
```

Ohne Schlüssel antwortet die Box **401**, ohne konfigurierten Schlüssel auf der Box
**503** (fail-closed — nie offen).

## Was drin ist

- `mops_scetchup.rb` — Loader, registriert die Extension.
- `mops_scetchup/main.rb` — liest das markierte Bauteil, fragt den Mops (Fake oder Box),
  schreibt die Antwort ins AttributeDictionary `mops`, zeigt die Rückfrage als Dialog
  mit drei grossen Knöpfen und „Jetzt nicht — schick's mir".
- `docs/box-endpoint.md` — der Vertrag mit der Box.
- `install.sh` / `paket.sh` — einhängen bzw. paketieren.

## Testen (Raphi klickt)

1. Ein **Bauteil** zeichnen und **markieren**. Am meisten sieht man, wenn der Name
   Raphaels Konvention folgt, z. B. `UG_AW_Waende_365mm_PP4-0,50_KG 340.001_7`.
2. **Extensions-Menü → „Mops fragen"** (oder in der Toolbar „Malmops").
3. Es erscheint „🐶 Mops hat gelesen: UG · Außenwand · 36,5 cm · PP4-0,50 · KG 340".
   Im Fake-Modus mit `[FAKE — ohne Box]`.
4. Danach **eine** Frage mit drei Knöpfen und „Jetzt nicht — schick's mir".
5. Prüfen, dass das Attribut wirklich am Bauteil klebt — Ruby-Konsole:
   ```ruby
   e = Sketchup.active_model.selection[0]
   e.get_attribute('mops', 'kg')       # => "340"
   e.get_attribute('mops', 'material') # => "PP4-0,50"
   ```
6. Und dass die Antwort wirklich **angekommen** ist — das ist der eigentliche Nachweis:
   ```bash
   ssh mops 'python3 ~/mops-api/scripts/ablage_zeigen.py'
   ```
   Steht die Zeile da, ist es echt. Steht sie nicht da, war es eine Vorführung.

## Von Fake auf echt

In `mops_scetchup/main.rb`: `FAKE = false`.
URL und Schlüssel kommen aus `~/.mops-sketchup.json` (siehe oben), nicht aus dem Code.

Auf der Box muss `SKETCHUP_SCHLUESSEL` in der `.env` stehen und der Dienst neu
gestartet sein. Ohne das antworten die Routen **503** — fail-closed, nie offen.

## Nächste Schritte

- Echtes Mops-Icon (16/24 px PNG als `mops_scetchup/icon.png`) — dann trägt der Toolbar-Knopf das Gesicht.
- Rückrichtung: „Mops-Katalog"-Panel (Bauteil, das der Mops schon kennt, direkt platzieren) — HtmlDialog.
- Mengen statt nur Maße (Fläche/Volumen) für flächige Bauteile.
