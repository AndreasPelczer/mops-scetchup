# mops-scetchup — der Malmops für SketchUp (Bogen 4, Spike)

Eine kleine SketchUp-Extension mit einem Mops-Knopf: markiertes Bauteil an den Mops schicken,
und die LV-Info (Baustein, Aufwandswert, Preis) landet als **Attribut am Bauteil**. Damit trägt
die Zeichnung die LV-Wahrheit selbst — beim DXF/IFC-Export muss der Mops-Leser nicht mehr raten.

**Stand: Spike.** Läuft im **FAKE-Modus** — der Mops antwortet lokal mit einer Dummy-Zuordnung,
damit die ganze Kette (Bauteil lesen → schicken → Attribut schreiben → Meldung) **ohne Box**
testbar ist. Der echte Weg (POST an die Box) ist eingebaut, aber per `FAKE = true` aus.

## Was drin ist

- `mops_scetchup.rb` — Loader, registriert die Extension.
- `mops_scetchup/main.rb` — der Code: liest das markierte Bauteil (Name + Maße), fragt den Mops
  (Fake oder Box), schreibt die Antwort ins AttributeDictionary `mops` am Bauteil, zeigt eine Meldung.
- `docs/box-endpoint.md` — Spec für den echten Box-Endpunkt `POST /sketchup/match` (Schritt 2).

## Installieren (auf dem Rechner mit SketchUp — aktuell Raphis Mac)

SketchUp lädt Extensions aus seinem **Plugins-Ordner**. Auf dem Mac:

```
~/Library/Application Support/SketchUp <VERSION>/SketchUp/Plugins/
```

Aus diesem Repo **beide** dort hin verlinken (Symlink, dann zieht ein `git pull` die Updates gleich mit):

```bash
REPO=~/XcodeProjects/mops-scetchup
PLUG="$HOME/Library/Application Support/SketchUp 2024/SketchUp/Plugins"   # Version anpassen
ln -s "$REPO/mops_scetchup.rb"  "$PLUG/mops_scetchup.rb"
ln -s "$REPO/mops_scetchup"     "$PLUG/mops_scetchup"
```

(Statt Symlink geht auch Kopieren — dann muss man nach jedem Update neu kopieren.)

SketchUp neu starten. Unter **Fenster → Erweiterungs-Manager** sollte „Malmops" auftauchen.

## Testen (Raphi klickt)

1. Eine **Gruppe oder Komponente** zeichnen (z. B. eine flache Platte → wird als „Pflaster" erkannt)
   und **markieren**.
2. **Extensions-Menü → „Mops fragen"** (oder in der Toolbar „Malmops" auf den Knopf).
3. Es erscheint eine Meldung „🐶 Mops sagt: …" mit Baustein/Aufwandswert/Preis (im Fake mit `[FAKE]`).
4. Prüfen, dass das Attribut wirklich am Bauteil klebt — Ruby-Konsole:
   ```ruby
   e = Sketchup.active_model.selection[0]
   e.get_attribute('mops', 'aufwandswert_key')   # => "pflasterarbeiten.verbundpflaster_verlegen"
   ```

Wenn das steht, ist das Konzept bewiesen.

## Von Fake auf echt (Schritt 2)

In `mops_scetchup/main.rb`:
- `FAKE = false`
- `MOPS_URL` auf die Box zeigen (Tailscale-Hostname/-IP der Box, Port der mops-api).

Dann braucht die Box den Endpunkt `POST /sketchup/match` — Spec in `docs/box-endpoint.md`.

## Nächste Schritte

- Echtes Mops-Icon (16/24 px PNG als `mops_scetchup/icon.png`) — dann trägt der Toolbar-Knopf das Gesicht.
- Rückrichtung: „Mops-Katalog"-Panel (Bauteil, das der Mops schon kennt, direkt platzieren) — HtmlDialog.
- Mengen statt nur Maße (Fläche/Volumen) für flächige Bauteile.
