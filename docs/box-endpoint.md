# Box-Endpunkt: `POST /sketchup/match` (Schritt 2)

Der echte Weg, wenn die Extension aus dem Fake-Modus geht (`FAKE = false` in `main.rb`).
Lebt in **mops-api** (Python, auf der Box) — NICHT in diesem Repo. Hier nur der Vertrag.

## Anfrage (von SketchUp)

```
POST /sketchup/match
Content-Type: application/json

{
  "name": "Pasand Vollstein 39x19_5x8cm",
  "laenge_m": 0.39,
  "breite_m": 0.195,
  "hoehe_m": 0.08
}
```

## Antwort (von der Box)

```json
{
  "baustein": "Betonverbundpflaster verlegen",
  "aufwandswert_key": "pflasterarbeiten.verbundpflaster_verlegen",
  "einheit": "m2",
  "preis": 12.5,
  "quelle": "STLB"
}
```

Die Extension schreibt **alle Felder** der Antwort als Attribute ins Dictionary `mops` am Bauteil.

## Was die Box intern tut (wiederverwendbar, existiert schon)

Der Match ist genau der, den iMOPS lokal fährt — die Box kann dieselbe Logik anbieten:

1. `name` durch den vorhandenen Matcher (STLB-Baustein über kurztext + tags) →
   `aufwandswert_key`. Ist im iOS-Client als `STLBKatalog.finde` / `BauTextMatcher` gebaut;
   für die Box als Python-Port oder als Aufruf gegen dieselben YAMLs
   (`stlb_bausteine.yaml`, `aufwandswerte.yaml`).
2. `aufwandswert_key` → Richtwert (Kolonne, Stunden) aus `aufwandswerte.yaml`.
3. Preis aus Kolonne × Firmensätzen (wie `LeistungskatalogService`), oder erstmal nur der
   Aufwandswert ohne Preis (Preis = 0), bis die Preis-Logik serverseitig steht.

## Sicherheit / Datenhoheit

- Nur über **Tailscale** erreichbar (kein öffentliches Internet) — Preise bleiben im eigenen Netz.
- Kein Auth im Spike; für den Dauerbetrieb ein simpler Token-Header, wenn gewünscht.

## Offene Punkte

- `name` allein reicht oft nicht (Wände heißen generisch) — später zusätzlich die Maße/Fläche
  in den Match einbeziehen, oder die SketchUp-Namenskonvention (`ifc_namen`-Idee) erzwingen.
- Rückrichtung (Katalog → SketchUp) braucht `GET /sketchup/katalog` (Liste bekannter Bausteine
  + Standardmaße), damit das „Mops-Katalog"-Panel Bauteile platzieren kann.
