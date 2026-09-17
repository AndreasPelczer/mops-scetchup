# mops_scetchup/main.rb
# Bogen 4 — der "Malmops": markiertes Bauteil an den Mops, LV-Info zurück ans Bauteil.
#
# EHRLICH (Spike): FAKE = true antwortet lokal mit einer Dummy-Zuordnung, damit die ganze
# Kette (Bauteil lesen -> schicken -> Attribut schreiben -> Meldung) OHNE Box testbar ist.
# Für den echten Betrieb: FAKE = false und MOPS_URL auf die Box (Tailscale) zeigen; dann
# ruft die Extension POST /sketchup/match (Spec in docs/box-endpoint.md).

require 'sketchup.rb'
require 'json'

module DeadRabbit
  module MopsScetchup

    # --- Konfiguration ---
    FAKE     = true                              # true = ohne Box, lokale Dummy-Antwort
    MOPS_URL = 'http://mops-box:8000'.freeze     # Box über Tailscale; + '/sketchup/match'
    DICT     = 'mops'.freeze                      # AttributeDictionary am Bauteil

    # --- Aktion: markiertes Bauteil an den Mops ---
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
        schreibe_und_melde(model, ent, info, fake_antwort(info))
      else
        frage_mops(model, ent, info) # asynchron, meldet sich im Callback
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
        'hoehe_m'  => runde(b.depth.to_m)
      }
    end

    def self.runde(meter)
      (meter * 1000.0).round / 1000.0
    end

    # Fake: plausible Zuordnung aus den Maßen (flach & dünn -> Pflaster). Nur zum Testen der Kette.
    def self.fake_antwort(info)
      if info['hoehe_m'] <= 0.15
        {
          'baustein'         => 'Betonpflaster verlegen',
          'aufwandswert_key' => 'pflasterarbeiten.verbundpflaster_verlegen',
          'einheit'          => 'm2',
          'preis'            => 12.5,
          'quelle'           => 'FAKE'
        }
      else
        {
          'baustein'         => 'Mauerwerk',
          'aufwandswert_key' => 'mauerarbeiten.wand',
          'einheit'          => 'm2',
          'preis'            => 45.0,
          'quelle'           => 'FAKE'
        }
      end
    end

    # Echter Weg: POST an die Box, Antwort im Callback verarbeiten.
    def self.frage_mops(model, ent, info)
      url = MOPS_URL + '/sketchup/match'
      req = Sketchup::Http::Request.new(url, Sketchup::Http::POST)
      req.headers = { 'Content-Type' => 'application/json' }
      req.body = info.to_json
      req.start do |_request, response|
        begin
          antwort = JSON.parse(response.body)
          schreibe_und_melde(model, ent, info, antwort)
        rescue => e
          UI.messagebox("Mops-Antwort nicht lesbar: #{e.message}")
        end
      end
    rescue => e
      UI.messagebox("Konnte den Mops nicht erreichen: #{e.message}\n(URL: #{url})")
    end

    # Antwort als Attribut ans Bauteil schreiben + kurze Meldung. Das Attribut IST die Verbindung:
    # beim DXF/IFC-Export trägt das Bauteil die LV-Wahrheit mit — kein Raten mehr im Mops-Leser.
    def self.schreibe_und_melde(model, ent, info, antwort)
      model.start_operation('Mops-Zuordnung', true)
      antwort.each { |k, v| ent.set_attribute(DICT, k, v) }
      ent.set_attribute(DICT, 'name', info['name'])
      model.commit_operation

      fake = antwort['quelle'].to_s == 'FAKE' ? '  [FAKE]' : ''
      UI.messagebox(
        "🐶 Mops sagt:\n" \
        "Bauteil: #{info['name']} " \
        "(#{info['laenge_m']} × #{info['breite_m']} × #{info['hoehe_m']} m)\n" \
        "→ #{antwort['baustein']} (#{antwort['aufwandswert_key']})\n" \
        "Preis: #{antwort['preis']} €/#{antwort['einheit']}#{fake}\n\n" \
        "Ist jetzt als Attribut '#{DICT}' am Bauteil gespeichert."
      )
    end

    # --- Menü + Toolbar (einmalig) ---
    unless defined?(@ui_ready) && @ui_ready
      cmd = UI::Command.new('Mops fragen') { DeadRabbit::MopsScetchup.bauteil_an_mops }
      cmd.tooltip = 'Markiertes Bauteil an den Mops schicken'
      cmd.status_bar_text = 'Fragt den Mops zum markierten Bauteil und speichert die LV-Info daran.'

      icon = File.join(File.dirname(__FILE__), 'icon.png')
      if File.exist?(icon)
        cmd.small_icon = icon
        cmd.large_icon = icon
      end

      UI.menu('Extensions').add_item(cmd)          # Menü braucht kein Icon
      toolbar = UI::Toolbar.new('Malmops')
      toolbar.add_item(cmd)
      toolbar.show

      @ui_ready = true
    end

  end
end
