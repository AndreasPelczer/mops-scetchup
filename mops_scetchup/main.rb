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

    FAKE      = true                              # true = ohne Box, lokale Antwort
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

      melde(info, antwort)
      zeige_frage(frage) if frage
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

      icon = File.join(File.dirname(__FILE__), 'icon.png')
      if File.exist?(icon)
        cmd.small_icon = icon
        cmd.large_icon = icon
      end

      UI.menu('Extensions').add_item(cmd)
      toolbar = UI::Toolbar.new('Malmops')
      toolbar.add_item(cmd)
      toolbar.show

      @ui_ready = true
    end

  end
end
