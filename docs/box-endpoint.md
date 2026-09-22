# Box-Endpunkte: `/sketchup/*`

Der echte Weg, wenn die Extension aus dem Fake-Modus geht (`FAKE = false` in `main.rb`).
Lebt in **mops-api** (Python, auf der Box) — NICHT in diesem Repo. Hier nur der Vertrag.

**Gebaut am 22.09.2026** (`mops-api`, Branch `feature/ablage-nachweise`).

---

## 🔴 Was sich gegenüber der ersten Fassung geändert hat

Die erste Fassung dieser Datei versprach `baustein`, `aufwandswert_key` und `preis`.
**Nachgemessen: das kann die Box nicht.** Im Backend gibt es keinen STLB-Matcher und
keine Aufwandswerte — die liegen im iOS-Client (`Resources/Knowledge/`). Diese Felder
kommen deshalb als `null` zurück. Eine plausible Zahl wäre schlimmer als keine: sie
sieht aus wie Wissen.

Was die Box **stattdessen** kann, und das ist für Raphael mehr wert: sie liest **seine
eigene Namenskonvention** (`api/services/ifc_namen.py`) und sagt ihm, was sie verstanden
hat — Geschoss, Bauteilart, Dicke, Güte, Kostengruppe.

Und sie sagte „kein Auth im Spike, nur über Tailscale". Die Box hängt aber über
Cloudflare **im offenen Internet**. Ein Schreib-Endpunkt ohne Schloss wäre dort eine
offene Tür. Deshalb jetzt ein Schlüssel im Header, fail-closed.

---

## Zugang

Jeder Aufruf braucht den Header:

```
X-Mops-Schluessel: <der Schlüssel>
```

Auf der Box in der `.env`: `SKETCHUP_SCHLUESSEL=...`
Ohne konfigurierten Schlüssel antworten alle Routen **503** — nie offen.

Auf Raphaels Rechner liegt er in `~/.mops-sketchup.json` (nicht im Repo):

```json
{ "url": "http://mops-box:8000", "schluessel": "...", "wer": "Raphael" }
```

---

## `POST /sketchup/match`

### Anfrage (von SketchUp)

```json
{
  "name": "UG_AW_Waende_365mm_PP4-0,50_KG 340.001_7",
  "laenge_m": 4.2,
  "breite_m": 0.365,
  "hoehe_m": 2.75,
  "wer": "raphael"
}
```

### Antwort

```json
{
  "geschoss": "UG",
  "art": "AW",
  "art_klartext": "Außenwand",
  "dicke_m": 0.365,
  "material": "PP4-0,50",
  "kg": "340",
  "kg_voll": "340.001",
  "erkannt": true,

  "baustein": null,
  "aufwandswert_key": null,
  "einheit": null,
  "preis": null,
  "quelle": "namenskonvention",

  "hinweis": null,
  "frage": {
    "id": 1,
    "frage": "Du hast eine Aussenwand mit 36,5 cm gezeichnet. Was kommt bei dir unten drunter?",
    "optionen": ["Kimmschicht", "Direkt auf die Abdichtung", "Sag ich dir"],
    "gegenstand": "UG_AW_Waende_365mm_PP4-0,50_KG 340.001_7"
  }
}
```

Die Extension schreibt alle **flachen** Felder als Attribute ins Dictionary `mops` am
Bauteil. `frage` ist Gespräch, kein Attribut — sie wird als Dialog gezeigt.

`hinweis` ist gesetzt, wenn etwas nicht zusammenpasst (z. B. Porenbeton-Güte gegen
Wanddicke). **Der Mops korrigiert nicht, er sagt Bescheid.**

### Die Frage

Kommt **höchstens eine**, und **höchstens alle 20 Stunden** pro Person. Eine noch offene
Frage geht immer vor einer neuen. Reihenfolge der Quellen:

1. Eine **Lücke** — der Mops konnte etwas am Namen nicht lesen (ehrlichste Frage)
2. Ein **Widerspruch** — Güte passt nicht zur Dicke
3. Eine **offene Fachfrage** aus `config/fragen.yaml`, passend zur Bauteilart

🔴 Eine Katalogfrage darf **keine Ziffer** enthalten. „Stimmen die 95 % Ev2?" wird
weggenickt; gefragt wird nach dem Wert, nie mit dem Wert. Das prüft
`fragen_werkstatt._pruefe_katalog` beim Laden — die Regel steht im Code, nicht nur hier.
Zahlen dürfen nur aus dem stammen, was Raphael **selbst** in den Namen geschrieben hat.

---

## `POST /sketchup/antwort`

```json
{ "frage_id": 1, "antwort": "Kimmschicht", "verschoben": false, "wer": "Raphael" }
```

Wegklicken: `{"frage_id": 1, "verschoben": true, "wer": "Raphael"}`

Antwort:

```json
{ "gespeichert": true, "nachweis_id": 3,
  "text": "Danke. Steht jetzt als 'geprüft von Raphael' drin." }
```

🔴 **Verschieben ist kein Nein.** Die Frage bleibt offen und kommt wieder, nur nicht
sofort. Verschwände sie, hätte der Mops eine Auskunft, die nie jemand gegeben hat.
Eine leere Antwort gilt ebenfalls als verschoben.

---

## `GET /sketchup/stand`

```json
{ "nachweise": 3, "fragen_offen": 0, "fragen_beantwortet": 1 }
```

Zum Nachsehen, ob wirklich etwas ankam. Ausführlicher auf der Box:

```bash
ssh mops 'python3 ~/mops-api/scripts/ablage_zeigen.py'
```

**Das ist der Nachweis.** Steht die Zeile da, ist es echt. Steht sie nicht da, war es
eine Vorführung — dieser Unterschied hat hier schon einmal Wochen gekostet
(Preise lagen „drin" und waren es nie).

---

## Wo es landet

`api/services/ablage.py` — eine SQLite-Datei (`~/mops-api/data/ablage.db`, per
`MOPS_ABLAGE` verlegbar). Zwei Regeln stehen dort im Code:

- **Ohne Zeugen kein Nachweis** — ein Eintrag ohne `wer` wird abgewiesen
- **Nichts wird überschrieben** — eine Korrektur ist eine neue Zeile, die auf die alte zeigt

---

## Offene Punkte

- **Der Preis.** Kommt erst, wenn der Matcher aus dem iOS-Client als Python-Port oder
  als gemeinsame YAML-Quelle auf der Box liegt. Bis dahin ehrlich `null`.
- **Rückrichtung** (Katalog → SketchUp) braucht `GET /sketchup/katalog`, damit ein
  „Mops-Katalog"-Panel Bauteile platzieren kann.
- **Die Fragen in `config/fragen.yaml` sind Entwürfe** — von einer Maschine formuliert,
  nicht vom Fach. Sie behaupten nichts, sie fragen. Was Raphael beantwortet, wird
  geprüftes Wissen mit seinem Namen; was er nicht beantwortet, bleibt ungeprüft.
