# mops_scetchup/main.rb
# Der "Malmops" — markiertes Bauteil an den Mops, und der Mops fragt EINE Sache zurück.
#
# Andreas am 22.09.2026: "es muss aussehen als ob das plugin mit ihm spielt. jeden Tag
# oder so eine einzige frage, die er auch wegklicken kann."
#
# Raphael zeichnet ohnehin. Also holt der Mops seinen Beitrag dort ab, wo er sowieso
# ist, statt ihn zu einem Prozess zu holen. Was er antwortet, bekommt SEINEN Namen:
# "geprüft von Raphael" steht später bei dem, der den Arbeitsschritt draussen liest.
#
# EHRLICH: FAKE = true antwortet lokal, damit die Kette ohne Box testbar ist.
# Der Mops erfindet dabei KEINEN Preis — im Backend gibt es (Stand 22.09.) keinen
# Matcher und keine Aufwandswerte. Er sagt, was er an Raphaels Namenskonvention
# gelesen hat. Eine plausible Zahl wäre schlimmer als keine.

require 'sketchup.rb'
require 'json'

module DeadRabbit
  module MopsScetchup

    # Steht auf false: der echte Weg zur Box. Fehlt der Schluessel, sagt das
    # Plugin genau das — statt still eine erfundene Antwort zu zeigen.
    # Zum Vorfuehren ohne Box: auf true stellen.
    FAKE      = false
    MOPS_URL  = 'http://mops-box:8080'.freeze     # Box über Tailscale
    DICT      = 'mops'.freeze                     # AttributeDictionary am Bauteil
    KONFIG    = File.join(Dir.home, '.mops-sketchup.json').freeze
    WER       = 'Raphael'.freeze

    # --- Konfiguration: URL und Schlüssel liegen NICHT im Repo ---------------
    # Der Schlüssel ist ein Geheimnis. Er kommt aus ~/.mops-sketchup.json:
    #   { "url": "http://mops-box:8080", "schluessel": "...", "wer": "Raphael" }
    def self.konfig
      @konfig ||= begin
        if File.exist?(KONFIG)
          JSON.parse(File.read(KONFIG))
        else
          {}
        end
      rescue => e
        UI.messagebox("Konfig unlesbar (#{KONFIG}):\n#{e.message}")
        {}
      end
    end

    def self.url;        konfig['url']        || MOPS_URL; end
    def self.schluessel; konfig['schluessel'] || ''; end
    def self.wer;        konfig['wer']        || WER; end

    # --- Aktion: markiertes Bauteil an den Mops ------------------------------
    def self.bauteil_an_mops
      model = Sketchup.active_model
      sel = model.selection
      if sel.empty?
        UI.messagebox('Erst ein Bauteil markieren (Gruppe oder Komponente).')
        return
      end
      ent = sel.find { |e| e.respond_to?(:bounds) } || sel.first
      info = masse(ent)

      if FAKE
        verarbeite(model, ent, info, fake_antwort(info))
      else
        frage_mops(model, ent, info)
      end
    end

    # Maße + Name aus dem Bauteil ziehen (SketchUp-Innenmaß = Zoll -> Meter).
    def self.masse(ent)
      b = ent.bounds
      name = if ent.respond_to?(:definition) && ent.definition
               ent.definition.name
             elsif ent.respond_to?(:name) && !ent.name.to_s.empty?
               ent.name
             else
               ent.typename
             end
      {
        'name'     => name.to_s,
        'laenge_m' => runde(b.width.to_m),
        'breite_m' => runde(b.height.to_m),
        'hoehe_m'  => runde(b.depth.to_m),
        'wer'      => wer.downcase
      }
    end

    def self.runde(meter)
      (meter * 1000.0).round / 1000.0
    end

    # Fake: liest den Namen grob so, wie es die Box tut. KEIN Preis.
    def self.fake_antwort(info)
      n = info['name'].to_s
      geschoss = n[/^(UG|EG|OG\d?|DG|AB)_/, 1]
      art      = n[/_(AW|IW|FT|EB|DK)_/, 1]
      dicke    = n[/_(\d+)mm/, 1]
      {
        'geschoss' => geschoss,
        'art'      => art,
        'dicke_m'  => dicke ? dicke.to_f / 1000.0 : nil,
        'erkannt'  => !geschoss.nil?,
        'quelle'   => 'FAKE',
        'frage'    => {
          'id'         => 0,
          'frage'      => 'Was kommt bei dir unter diese Wand?',
          'optionen'   => ['Kimmschicht', 'Direkt auf die Abdichtung', 'Sag ich dir'],
          'gegenstand' => n
        }
      }
    end

    # --- Echter Weg: POST an die Box ----------------------------------------
    def self.frage_mops(model, ent, info)
      if schluessel.empty?
        UI.messagebox("Es fehlt der Zugangsschlüssel.\nLege #{KONFIG} an:\n" \
                      '{ "url": "...", "schluessel": "...", "wer": "Raphael" }')
        return
      end
      ziel = url + '/sketchup/match'
      req = Sketchup::Http::Request.new(ziel, Sketchup::Http::POST)
      req.headers = { 'Content-Type' => 'application/json',
                      'X-Mops-Schluessel' => schluessel }
      req.body = info.to_json
      req.start do |_request, response|
        begin
          if response.status_code >= 400
            UI.messagebox("Der Mops sagt Nein (#{response.status_code}).\n" \
                          "Stimmt der Schlüssel in #{KONFIG}?")
          else
            verarbeite(model, ent, info, JSON.parse(response.body))
          end
        rescue => e
          UI.messagebox("Mops-Antwort nicht lesbar: #{e.message}")
        end
      end
    rescue => e
      UI.messagebox("Konnte den Mops nicht erreichen: #{e.message}\n(#{ziel})")
    end

    # --- Antwort ans Bauteil schreiben, dann (vielleicht) die Frage ----------
    def self.verarbeite(model, ent, info, antwort)
      frage = antwort['frage']

      model.start_operation('Mops-Zuordnung', true)
      antwort.each do |k, v|
        # 'frage' ist Gespräch, kein Bauteil-Attribut. Und nichts Verschachteltes
        # ins Dictionary: SketchUp kann dort nur einfache Werte halten.
        next if k == 'frage'
        next if v.is_a?(Hash) || v.is_a?(Array)
        ent.set_attribute(DICT, k, v) unless v.nil?
      end
      ent.set_attribute(DICT, 'name', info['name'])
      model.commit_operation

      # 🔴 EIN Fenster. Am 22.09. sass Raphael vor zwei Fenstern hintereinander
      # ("er hat ok gedrueckt ... und macht aehhh, waaas, jetzt, wo aehm") —
      # erst eine Meldung zum Wegklicken, dann ohne Erklaerung noch eine Frage.
      # Ein Blick, eine Entscheidung.
      zeige_ergebnis(info, antwort, frage)
    end

    # Kurz und ohne Zahlen, die keiner geprüft hat.
    def self.melde(info, antwort)
      gelesen = []
      gelesen << antwort['geschoss'] if antwort['geschoss']
      gelesen << (antwort['art_klartext'] || antwort['art']) if antwort['art'] || antwort['art_klartext']
      # 36,5 statt 36: Raphael hat 365mm geschrieben. Falsch zitiert = weggeklickt.
      gelesen << "#{format('%g', (antwort['dicke_m'].to_f * 100).round(1)).tr('.', ',')} cm" if antwort['dicke_m']
      gelesen << antwort['material'] if antwort['material']
      gelesen << "KG #{antwort['kg']}" if antwort['kg']

      text = "🐶 Mops hat gelesen:\n"
      text += gelesen.empty? ? "(an dem Namen konnte ich nichts erkennen)\n"
                             : "#{gelesen.join(' · ')}\n"
      text += "\n⚠️ #{antwort['hinweis']}\n" if antwort['hinweis']
      text += "\n[FAKE — ohne Box]" if antwort['quelle'].to_s == 'FAKE'
      Sketchup.status_text = text.split("\n")[1].to_s
      UI.messagebox(text)
    end

    # --- EIN Fenster: was gelesen wurde UND die Frage ------------------------
    def self.zeige_ergebnis(info, antwort, frage)
      unless defined?(UI::HtmlDialog)
        melde(info, antwort)
        zeige_frage_schlicht(frage) if frage
        return
      end

      dlg = UI::HtmlDialog.new(
        :dialog_title => 'Der Mops', :scrollable => true, :resizable => true,
        :width => 620, :height => 560, :min_width => 480, :min_height => 380,
        :style => UI::HtmlDialog::STYLE_DIALOG,
        :preferences_key => 'com.deadrabbit.mops.ergebnis'
      )
      dlg.set_html(ergebnis_html(info, antwort, frage))
      dlg.add_action_callback('antworten') do |_c, wahl|
        dlg.close
        sende_antwort(frage, wahl, false) if frage
        nil
      end
      dlg.add_action_callback('spaeter') do |_c, _x|
        dlg.close
        sende_antwort(frage, nil, true) if frage
        nil
      end
      dlg.add_action_callback('zu') do |_c, _x|
        dlg.close
        nil
      end
      dlg.center
      dlg.show
    end

    def self.ergebnis_html(info, antwort, frage)
      gelesen = []
      gelesen << ['Geschoss', antwort['geschoss']]
      gelesen << ['Bauteil', antwort['art_klartext'] || antwort['art']]
      if antwort['dicke_m']
        gelesen << ['Dicke', format('%g', (antwort['dicke_m'].to_f * 100).round(1)).tr('.', ',') + ' cm']
      end
      gelesen << ['Güte', antwort['material']]
      gelesen << ['Kostengruppe', antwort['kg_voll'] || antwort['kg']]
      zeilen = gelesen.select { |_k, v| v && v.to_s != '' }

      tabelle = zeilen.map { |k, v|
        "<tr><td class=k>#{k}</td><td class=v>#{v}</td></tr>"
      }.join
      fehlt = gelesen.select { |_k, v| v.nil? || v.to_s == '' }
                     .map { |k, _v| k }.join(', ')

      knoepfe = ''
      if frage
        knoepfe = frage['optionen'].map { |o|
          "<button class=w onclick=\"sketchup.antworten('#{o.gsub("'", ' ')}')\">#{o}</button>"
        }.join
      end

      <<-HTML
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{font:15px -apple-system,system-ui,sans-serif;margin:0;padding:24px;
      background:#faf7f2;color:#2b2b2b}
 .kopf{font-size:13px;color:#9a7b4f;letter-spacing:.08em;text-transform:uppercase}
 .name{font-size:17px;color:#6b6b6b;margin:4px 0 18px;word-break:break-all}
 table{border-collapse:collapse;width:100%;margin-bottom:6px}
 td{padding:9px 4px;border-bottom:1px solid #eee4d4;font-size:17px}
 td.k{color:#8a8a8a;width:150px;font-size:14px;text-transform:uppercase}
 td.v{font-weight:600}
 .fehlt{background:#fff4e5;border-left:4px solid #c8a063;border-radius:0 8px 8px 0;
        padding:11px 14px;font-size:15px;margin:14px 0}
 .frage{font-size:19px;line-height:1.35;margin:26px 0 16px}
 button.w{display:block;width:100%;margin:0 0 9px;padding:14px 16px;font-size:16px;
          text-align:left;border:1px solid #e0d6c6;border-radius:10px;background:#fff;
          cursor:pointer;color:#2b2b2b}
 button.w:hover{background:#fff8ec;border-color:#c8a063}
 .spaeter{margin-top:12px;background:transparent;border:none;color:#8a8a8a;
          font-size:14px;padding:8px;cursor:pointer;width:100%}
 .zu{margin-top:18px;width:100%;padding:13px;border:0;border-radius:10px;
     background:#c8a063;color:#fff;font-size:16px;font-weight:600;cursor:pointer}
</style></head><body>
 <div class=kopf>🐶 Das hab ich gelesen</div>
 <div class=name>#{info['name']}</div>
 <table>#{tabelle}</table>
 #{fehlt.empty? ? '' : "<div class=fehlt>Nicht gefunden: <b>#{fehlt}</b> — steht das im Namen?</div>"}
 #{frage ? "<div class=frage>#{frage['frage']}</div>#{knoepfe}<button class=spaeter onclick=\"sketchup.spaeter('')\">Jetzt nicht</button>" : "<button class=zu onclick=\"sketchup.zu('')\">Passt</button>"}
</body></html>
      HTML
    end

    # --- Was weiss der Mops ueber das ganze Modell? --------------------------
    def self.modell_durchsehen
      model = Sketchup.active_model
      namen = model.definitions.reject { |d| d.image? }.map { |d| d.name.to_s }
      if namen.empty?
        UI.messagebox('In diesem Modell sind keine Bauteile benannt.')
        return
      end
      if schluessel.empty?
        UI.messagebox("Es fehlt der Zugangsschlüssel (#{KONFIG}).")
        return
      end

      Sketchup.status_text = "Mops liest #{namen.length} Namen..."
      req = Sketchup::Http::Request.new(url + '/sketchup/modell', Sketchup::Http::POST)
      req.headers = { 'Content-Type' => 'application/json',
                      'X-Mops-Schluessel' => schluessel }
      req.body = { 'namen' => namen, 'wer' => wer.downcase }.to_json
      req.start do |_r, response|
        begin
          Sketchup.status_text = ''
          if response.status_code >= 400
            UI.messagebox("Der Mops sagt Nein (#{response.status_code}).")
          else
            zeige_modell(JSON.parse(response.body))
          end
        rescue => e
          UI.messagebox("Antwort nicht lesbar: #{e.message}")
        end
      end
    rescue => e
      Sketchup.status_text = ''
      UI.messagebox("Konnte den Mops nicht erreichen: #{e.message}")
    end

    def self.zeige_modell(d)
      dlg = UI::HtmlDialog.new(
        :dialog_title => 'Was der Mops aus deinen Namen liest',
        :scrollable => true, :resizable => true,
        :width => 900, :height => 680, :min_width => 560, :min_height => 400,
        :preferences_key => 'com.deadrabbit.mops.modell'
      )
      dlg.set_html(modell_html(d))
      dlg.center
      dlg.show
    end

    def self.modell_html(d)
      zeilen = d['zeilen'].map { |z|
        leer = ->(v) { (v.nil? || v.to_s == '') ? '<span class=x>—</span>' : v.to_s }
        dicke = z['dicke_m'] ? format('%g', (z['dicke_m'].to_f * 100).round(1)).tr('.', ',') : nil
        "<tr><td class=n>#{z['name']}</td>" \
        "<td>#{leer.call(z['geschoss'])}</td>" \
        "<td>#{leer.call(z['art_klartext'] || z['art'])}</td>" \
        "<td>#{leer.call(dicke)}</td>" \
        "<td>#{leer.call(z['material'])}</td>" \
        "<td>#{leer.call(z['kg'])}</td></tr>"
      }.join

      l = d['luecken'] || {}
      luecken = [['Geschoss', l['geschoss']], ['Bauteilart', l['art']],
                 ['Dicke', l['dicke']], ['Güte', l['material']],
                 ['Kostengruppe', l['kg']]]
                .select { |_k, v| v.to_i > 0 }
                .map { |k, v| "<li><b>#{v}×</b> ohne #{k}</li>" }.join

      <<-HTML
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{font:14px -apple-system,system-ui,sans-serif;margin:0;padding:22px;
      background:#faf7f2;color:#2b2b2b}
 h1{font-size:21px;margin:0 0 4px}
 .unter{color:#8a8a8a;font-size:14px;margin-bottom:18px}
 table{border-collapse:collapse;width:100%;font-size:14px}
 th{text-align:left;font-size:12px;color:#8a8a8a;text-transform:uppercase;
    padding:6px 8px;border-bottom:2px solid #e0d6c6}
 td{padding:7px 8px;border-bottom:1px solid #f0e8da}
 td.n{font-family:ui-monospace,Menlo,monospace;font-size:13px;color:#4b4b4b}
 .x{color:#c94f4f}
 .kasten{background:#fff;border-radius:12px;padding:16px 18px;margin-bottom:18px}
 .kasten ul{margin:8px 0 0;padding-left:20px} .kasten li{margin:3px 0}
 .gut{color:#2f7d32;font-weight:600}
</style></head><body>
 <h1>Was ich aus deinen Namen lese</h1>
 <div class=unter>#{d['bauteile']} Bauteile von #{d['gesehen']} Namen im Modell</div>
 <div class=kasten>
   #{luecken.empty? ? "<span class=gut>Bei allen steht alles drin.</span>" : "<b>Was mir fehlt:</b><ul>#{luecken}</ul>"}
 </div>
 <table>
  <tr><th>Name</th><th>Geschoss</th><th>Bauteil</th><th>Dicke cm</th><th>Güte</th><th>KG</th></tr>
  #{zeilen}
 </table>
</body></html>
      HTML
    end

    # --- Beispiel: so sieht ein Name aus, den der Mops versteht --------------
    # Andreas am 22.09.: „koennen wir mal eine Datei fuer ihn machen in SketchUp,
    # damit er sieht was wir erwarten? an einem Stein oder so."
    #
    # Kein Dokument zum Lesen — Bauteile zum Anfassen. Sie entstehen in SEINEM
    # Modell, er kann sie drehen, anklicken und den Mops-Knopf darauf druecken.
    #
    # Die Namen folgen seiner eigenen Konvention (ifc_namen). Das dritte Paar
    # ist Absicht: derselbe Stuetzwinkel einmal ohne und einmal mit Guete —
    # damit er den Unterschied sieht, statt ihn erklaert zu bekommen.
    BEISPIELE = [
      ['EG_AW_Waende_365mm_PP4-0,50_KG 330.001_1', 2.0, 0.365, 2.75,
       'Aussenwand: Geschoss, Bauteil, Dicke, Guete, Kostengruppe'],
      ['EG_IW_Waende_115mm_PP2-0,40_KG 340.002_1', 1.5, 0.115, 2.75,
       'Innenwand: dieselbe Ordnung, andere Dicke'],
      ['AB_FT_Stützwinkel L_995 B_120 H_550_KG 543.001_1', 0.995, 0.12, 0.55,
       'Dein Stuetzwinkel — so wie er heute heisst'],
      ['AB_FT_Stützwinkel L_995 B_120 H_550_C2530_KG 543.002_1', 0.995, 0.12, 0.55,
       'Derselbe mit Guete — das ist der Unterschied'],
    ].freeze

    def self.beispiel_bauen
      model = Sketchup.active_model
      model.start_operation('Mops-Beispiele', true)
      ents = model.active_entities
      x = 0.0
      gebaut = []

      BEISPIELE.each do |name, l, b, h, _hinweis|
        grp = ents.add_group
        flaeche = grp.entities.add_face(
          [x.m, 0, 0], [(x + l).m, 0, 0], [(x + l).m, b.m, 0], [x.m, b.m, 0])
        flaeche.pushpull(-h.m)
        grp.name = name
        grp.definition.name = name
        gebaut << grp
        x += l + 0.6
      end

      model.commit_operation
      model.active_view.zoom(gebaut)
      zeige_beispiel
    end

    def self.zeige_beispiel
      unless defined?(UI::HtmlDialog)
        UI.messagebox("Vier Beispiel-Bauteile stehen jetzt im Modell.\n" \
                      'Markiere eines und druecke den Mops-Knopf.')
        return
      end
      dlg = UI::HtmlDialog.new(
        :dialog_title => 'So sieht ein Name aus, den ich verstehe',
        :scrollable => true, :resizable => true,
        :width => 760, :height => 560, :min_width => 520,
        :preferences_key => 'com.deadrabbit.mops.beispiel'
      )
      zeilen = BEISPIELE.map { |name, _l, _b, _h, hinweis|
        teile = name.split('_')
        "<tr><td class=n>#{name}</td><td class=h>#{hinweis}</td></tr>"
      }.join
      dlg.set_html(<<-HTML)
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{font:15px -apple-system,system-ui,sans-serif;margin:0;padding:24px;
      background:#faf7f2;color:#2b2b2b}
 h1{font-size:20px;margin:0 0 4px}
 .unter{color:#8a8a8a;font-size:14px;margin-bottom:18px}
 table{border-collapse:collapse;width:100%}
 td{padding:10px 8px;border-bottom:1px solid #eee4d4;vertical-align:top}
 td.n{font-family:ui-monospace,Menlo,monospace;font-size:13px;color:#8a5a20;
      white-space:nowrap}
 td.h{font-size:14px;color:#6b6b6b}
 .bau{background:#fff;border-radius:12px;padding:16px 18px;margin-top:18px;
      font-size:15px;line-height:1.5}
 .bau b{color:#8a5a20}
</style></head><body>
 <h1>Vier Bauteile stehen jetzt in deinem Modell</h1>
 <div class=unter>Markiere eines und druecke den Mops-Knopf — dann siehst du, was ankommt.</div>
 <table>#{zeilen}</table>
 <div class=bau>
   Der Aufbau ist immer derselbe:<br>
   <b>Geschoss</b>_<b>Bauteil</b>_Bezeichnung_<b>Dicke</b>_<b>Guete</b>_<b>KG&nbsp;Nummer</b>_lfd<br><br>
   Geschoss: UG EG OG DG AB &middot; Bauteil: AW IW FT EB DK<br>
   Alles andere darfst du nennen wie du willst — der Mops sucht nur diese Teile.
 </div>
</body></html>
      HTML
      dlg.center
      dlg.show
    end

    # --- Die Frage: drei Knöpfe, ein Satz, wegklickbar -----------------------
    def self.zeige_frage(frage)
      if defined?(UI::HtmlDialog)
        zeige_frage_huebsch(frage)
      else
        zeige_frage_schlicht(frage)
      end
    end

    def self.zeige_frage_huebsch(frage)
      dlg = UI::HtmlDialog.new(
        :dialog_title => 'Der Mops fragt', :scrollable => false,
        :resizable => false, :width => 430, :height => 330,
        :style => UI::HtmlDialog::STYLE_DIALOG,
        :preferences_key => 'com.deadrabbit.mops.frage'
      )
      dlg.set_html(frage_html(frage))
      dlg.add_action_callback('antworten') do |_ctx, wahl|
        dlg.close
        sende_antwort(frage, wahl, false)
        nil
      end
      dlg.add_action_callback('spaeter') do |_ctx, _x|
        dlg.close
        sende_antwort(frage, nil, true)
        nil
      end
      dlg.center
      dlg.show
    end

    # Fallback für altes SketchUp: Auswahlliste statt Knöpfe.
    def self.zeige_frage_schlicht(frage)
      optionen = frage['optionen'] + ['Jetzt nicht']
      ergebnis = UI.inputbox(["#{frage['frage']}  "], [optionen.first],
                             [optionen.join('|')], 'Der Mops fragt')
      return unless ergebnis
      wahl = ergebnis.first
      sende_antwort(frage, wahl, wahl == 'Jetzt nicht')
    end

    def self.frage_html(frage)
      knoepfe = frage['optionen'].map do |o|
        "<button class='w' onclick=\"sketchup.antworten('#{o.gsub("'", " ")}')\">#{o}</button>"
      end.join
      <<-HTML
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  body{font:15px -apple-system,system-ui,sans-serif;margin:0;padding:22px;
       background:#faf7f2;color:#2b2b2b}
  .kopf{font-size:13px;color:#9a7b4f;letter-spacing:.08em;text-transform:uppercase}
  .was{font-size:12px;color:#8a8a8a;margin:2px 0 14px}
  .frage{font-size:19px;line-height:1.35;margin:0 0 20px}
  button{display:block;width:100%;margin:0 0 9px;padding:13px 16px;font-size:16px;
         text-align:left;border:1px solid #e0d6c6;border-radius:10px;background:#fff;
         cursor:pointer;color:#2b2b2b}
  button:hover{background:#fff8ec;border-color:#c8a063}
  .spaeter{margin-top:14px;background:transparent;border:none;color:#8a8a8a;
           font-size:14px;text-align:center;padding:8px}
  .spaeter:hover{background:transparent;color:#2b2b2b;text-decoration:underline}
</style></head><body>
  <div class="kopf">🐶 Der Mops fragt</div>
  <div class="was">#{frage['gegenstand']}</div>
  <div class="frage">#{frage['frage']}</div>
  #{knoepfe}
  <button class="spaeter" onclick="sketchup.spaeter('')">Jetzt nicht — schick's mir</button>
</body></html>
      HTML
    end

    # --- Antwort zurück an den Mops -----------------------------------------
    def self.sende_antwort(frage, wahl, verschoben)
      if FAKE
        UI.messagebox(verschoben ? "Alles gut — ich frag später nochmal.\n[FAKE]"
                                 : "Danke. Steht jetzt als 'geprüft von #{wer}' drin.\n[FAKE]")
        return
      end
      ziel = url + '/sketchup/antwort'
      req = Sketchup::Http::Request.new(ziel, Sketchup::Http::POST)
      req.headers = { 'Content-Type' => 'application/json',
                      'X-Mops-Schluessel' => schluessel }
      req.body = { 'frage_id' => frage['id'], 'antwort' => wahl,
                   'verschoben' => verschoben, 'wer' => wer }.to_json
      req.start do |_request, response|
        begin
          d = JSON.parse(response.body)
          Sketchup.status_text = d['text'].to_s
          UI.messagebox(d['text'].to_s)
        rescue => e
          UI.messagebox("Antwort ging nicht durch: #{e.message}")
        end
      end
    rescue => e
      UI.messagebox("Antwort ging nicht raus: #{e.message}")
    end

    # --- Menü + Toolbar (einmalig) ------------------------------------------
    unless defined?(@ui_ready) && @ui_ready
      cmd = UI::Command.new('Mops fragen') { DeadRabbit::MopsScetchup.bauteil_an_mops }
      cmd.tooltip = 'Markiertes Bauteil an den Mops schicken'
      cmd.status_bar_text = 'Fragt den Mops zum markierten Bauteil und speichert die LV-Info daran.'

      # Der Bau-Mops als Kopf mit Helm — die ganze Figur wird bei 24 Pixel
      # zu Matsch (dieselbe Falle wie beim k-MOPS-Drachen). Der orange Helm
      # ist das, was klein noch trägt.
      icon = File.join(File.dirname(__FILE__), 'icon.png')
      if File.exist?(icon)
        cmd.small_icon = icon
        cmd.large_icon = icon
      end

      # Zweiter Knopf: Raphael am 22.09. — „er will sehen was der mops an infos
      # hat, benennung und definitionsnamen." Die ehrlichste Art, ihm den Mops
      # zu zeigen: seine Namen, und daneben was davon ankommt.
      cmd2 = UI::Command.new('Was weisst du über mein Modell?') {
        DeadRabbit::MopsScetchup.modell_durchsehen
      }
      cmd2.tooltip = 'Alle Bauteilnamen durchsehen lassen'
      cmd2.status_bar_text = 'Zeigt, was der Mops aus deinen Namen liest — und was fehlt.'
      if File.exist?(icon)
        cmd2.small_icon = icon
        cmd2.large_icon = icon
      end

      cmd3 = UI::Command.new('Zeig mir ein Beispiel') {
        DeadRabbit::MopsScetchup.beispiel_bauen
      }
      cmd3.tooltip = 'Setzt vier richtig benannte Bauteile ins Modell'
      cmd3.status_bar_text = 'Vier Beispiel-Bauteile zum Anfassen und Ausprobieren.'
      if File.exist?(icon)
        cmd3.small_icon = icon
        cmd3.large_icon = icon
      end

      menue = UI.menu('Extensions')
      menue.add_item(cmd)
      menue.add_item(cmd2)
      menue.add_item(cmd3)
      toolbar = UI::Toolbar.new('Malmops')
      toolbar.add_item(cmd)
      toolbar.add_item(cmd2)
      toolbar.add_item(cmd3)
      toolbar.show

      @ui_ready = true
    end

  end
end
