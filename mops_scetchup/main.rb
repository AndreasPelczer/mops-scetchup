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
      name = echter_name(ent) || ent.typename   # Raphaels Gruppenname, nicht „Gruppieren#38"
      # 🔴 Raphael am 22.09.: "wir streiten um volumenkoerper die er braucht,
      # komponenten werden gezaehlt, gruppen nicht, mops wuerfel haben das
      # nicht, mops nutzlos." Er hat recht — fuer Mengen ist genau das
      # entscheidend:
      #   Komponente -> zaehlbar (40 Instanzen = 40 Stueck)
      #   Gruppe     -> jede fuer sich, nicht zaehlbar
      #   Volumenkoerper -> hat ein Volumen, daraus wird die Menge in m³
      # Ein Mops, der das nicht sagt, ist fuer einen Zeichner wertlos.
      ist_komponente = ent.is_a?(Sketchup::ComponentInstance)
      anzahl = (ent.respond_to?(:definition) && ent.definition) ?
                 ent.definition.instances.length : 1
      koerper = ent.respond_to?(:manifold?) ? ent.manifold? : false
      volumen = nil
      if koerper && ent.respond_to?(:volume)
        roh = ent.volume                      # Kubikzoll
        volumen = runde(roh / 61023.7440947323) if roh && roh > 0
      end

      {
        'name'      => name.to_s,
        'laenge_m'  => runde(b.width.to_m),
        'breite_m'  => runde(b.height.to_m),
        'hoehe_m'   => runde(b.depth.to_m),
        'typ'       => ist_komponente ? 'Komponente' : 'Gruppe',
        'zaehlbar'  => ist_komponente,
        'anzahl'    => anzahl,
        'koerper'   => koerper,
        'volumen_m3' => volumen,
        'wer'       => wer.downcase
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
      # 🔴 Zuerst das, wonach ein Zeichner fragt: zaehlbar? Koerper? Wieviel?
      gelesen << ['Art', info['typ'] +
                  (info['zaehlbar'] ? " · #{info['anzahl']}× im Modell"
                                    : ' · nicht zählbar')]
      gelesen << ['Volumen', info['koerper'] ?
                  (info['volumen_m3'] ?
                     "#{format('%g', info['volumen_m3']).tr('.', ',')} m³" \
                     " je Stück" : 'Körper, aber kein Volumen lesbar')
                  : 'KEIN Volumenkörper']
      if info['koerper'] && info['volumen_m3'] && info['anzahl'].to_i > 1
        gesamt = info['volumen_m3'] * info['anzahl'].to_i
        gelesen << ['Gesamt', "#{format('%g', gesamt.round(3)).tr('.', ',')} m³"]
      end
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
    # --- Mengen je Tag (13.10.2026) ------------------------------------------
    # Raphael legt alles Gleiche auf EINEN Tag („Schotter 16/30") — so arbeitet
    # man in SketchUp, der Tag sagt, WAS es ist. Der Mops las bisher nur Namen
    # und meldete eine „Gruppe#12" auf diesem Tag als Lücke. Jetzt zählt er je
    # Tag: Stück, geschlossene Körper und deren m³. Offene Gruppen (kein
    # Volumenkörper) werden gezählt, aber nie geschätzt — eine geratene Menge
    # sieht aus wie Wissen.
    #
    # Geschlossener Körper -> zählt, Volumen, nicht weiter hineinschauen.
    # Offen mit Gruppen drin -> hineinschauen (Tag vererbt sich nach innen).
    # Offen ohne Gruppen drin -> ein Stück „ohne Volumen".
    # 🔴 13.10.2026: Raphael benennt GRUPPEN. Der Name, den er vergibt, hängt an
    # der einzelnen Gruppe (ent.name); dahinter steht intern „Gruppieren#38".
    # Wir lasen den internen — und seine ganze Beschriftung kam nie an.
    # Reihenfolge jetzt: eigener Name -> Name der Eltern-Gruppe -> Komponentenname.
    AUTONAME = /\A(Gruppieren|Gruppe|Group|Komponente|Component)\s*#\d+\z/i

    def self.echter_name(ent, eltern_name = nil)
      eigen = ent.respond_to?(:name) ? ent.name.to_s.strip : ''
      return eigen unless eigen.empty? || eigen =~ AUTONAME
      return eltern_name if eltern_name
      d = ent.respond_to?(:definition) && ent.definition ? ent.definition.name.to_s : ''
      d.empty? || d =~ AUTONAME ? nil : d
    end

    # -> [tags, gesehen, teile]  teile = je (Name, Tag): Stück, m³, offen
    def self.mengen_je_tag(model)
      roh = model.layers[0]                       # „Untagged" (intern Layer0)
      summe = Hash.new { |h, k| h[k] = { 'tag' => k, 'stueck' => 0, 'koerper' => 0,
                                         'volumen_m3' => 0.0, 'offen' => 0 } }
      teile = Hash.new { |h, k| h[k] = { 'name' => k[0], 'tag' => k[1], 'stueck' => 0,
                                         'volumen_m3' => 0.0, 'offen' => 0 } }
      gesehen = 0
      besuche = lambda do |ents, eltern_tag, eltern_name, eltern_trafo, tiefe|
        return if tiefe > 30
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          gesehen += 1
          tag = (e.layer.nil? || e.layer == roh) ? eltern_tag : e.layer.name.to_s
          name = echter_name(e, eltern_name)
          if e.manifold? && (v = e.volume) && v > 0
            # e.volume kennt die eigene Skalierung; die der Eltern kommt dazu.
            m3 = v * trafo_faktor(eltern_trafo) / 61023.7440947323
            z = summe[tag]
            z['stueck'] += 1
            z['koerper'] += 1
            z['volumen_m3'] += m3
            t = teile[[name || 'ohne Namen', tag]]
            t['stueck'] += 1
            t['volumen_m3'] += m3
          else
            innen = e.definition.entities
            if innen.any? { |x| x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance) }
              besuche.call(innen, tag, name, eltern_trafo * e.transformation, tiefe + 1)
            else
              summe[tag]['stueck'] += 1
              summe[tag]['offen'] += 1
              t = teile[[name || 'ohne Namen', tag]]
              t['stueck'] += 1
              t['offen'] += 1
            end
          end
        end
      end
      besuche.call(model.entities, 'Ohne Tag', nil, Geom::Transformation.new, 0)
      liste = summe.values.map { |z| z.merge('volumen_m3' => runde(z['volumen_m3'])) }
      tl = teile.values.map { |z| z.merge('volumen_m3' => runde(z['volumen_m3'])) }
      [liste.sort_by { |z| z['tag'].downcase }, gesehen, tl.first(3000)]
    end

    # Was an die Box geht – EIN Ort für Knopf und Mitlesen.
    def self.modell_paket(model)
      tags, gesehen, teile = mengen_je_tag(model)
      namen = (teile.map { |t| t['name'] } +
               model.definitions.reject { |d| d.image? || d.group? }.map { |d| d.name.to_s })
              .reject { |n| n.empty? || n == 'ohne Namen' || n =~ AUTONAME }.uniq
      { 'namen' => namen, 'wer' => wer.downcase, 'tags' => tags, 'teile' => teile,
        'gruppen_gesehen' => gesehen, 'modell' => model.title.to_s }
    end

    # Wie stark eine Verschachtelung das Volumen streckt (Betrag der Determinante).
    def self.trafo_faktor(t)
      a = t.to_a
      (a[0] * (a[5] * a[10] - a[6] * a[9]) -
       a[4] * (a[1] * a[10] - a[2] * a[9]) +
       a[8] * (a[1] * a[6] - a[2] * a[5])).abs
    end

    def self.modell_durchsehen
      model = Sketchup.active_model
      paket = modell_paket(model)
      namen = paket['namen']
      if namen.empty? && paket['tags'].empty?
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
      req.body = paket.to_json
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

    # --- Mitlesen beim Speichern – nur mit Raphaels Ja (13.10.2026) ----------
    # Andreas: „er will nichts und doch alles." Darum: EINMAL fragen, beim ersten
    # Speichern. Sagt er Ja, schickt jedes Speichern Namen + Mengen je Tag an die
    # Box (höchstens alle 60 s), unten steht kurz „Mops hat mitgelesen".
    # Sagt er Nein, passiert nie etwas. Abschalten jederzeit im Menü.
    # Gemerkt in SketchUps eigenen Einstellungen, nicht im Modell.
    MITLESEN = 'mitlesen'.freeze   # nil = nie gefragt, 'ja', 'nein'

    def self.mitlesen
      Sketchup.read_default('MopsScetchup', MITLESEN, nil)
    end

    def self.mitlesen_setzen(wert)
      Sketchup.write_default('MopsScetchup', MITLESEN, wert)
    end

    def self.beim_speichern(model)
      return if schluessel.empty?
      if mitlesen.nil?
        wahl = UI.messagebox("Soll der Mops ab jetzt beim Speichern mitlesen?\n\n" \
                             "Dann schicke ich bei jedem Speichern deine Bauteilnamen und " \
                             "die Mengen je Tag an die Box – damit das Büro fragen kann " \
                             "„wieviel Schotter?“, ohne dass du was drückst.\n\n" \
                             'Abschalten geht jederzeit unter Erweiterungen.', MB_YESNO)
        mitlesen_setzen(wahl == IDYES ? 'ja' : 'nein')
      end
      leise_senden(model) if mitlesen == 'ja'
    end

    def self.leise_senden(model)
      return if model.nil?
      return if @zuletzt_leise && Time.now - @zuletzt_leise < 60
      @zuletzt_leise = Time.now
      paket = modell_paket(model)
      return if paket['namen'].empty? && paket['tags'].empty?
      req = Sketchup::Http::Request.new(url + '/sketchup/modell', Sketchup::Http::POST)
      req.headers = { 'Content-Type' => 'application/json',
                      'X-Mops-Schluessel' => schluessel }
      req.body = paket.to_json
      req.start do |_r, response|
        Sketchup.status_text = response.status_code < 400 ? 'Mops hat mitgelesen.' : ''
      end
    rescue => e
      puts "Malmops: mitlesen gescheitert: #{e.message}"
    end

    class Speicherwache < Sketchup::ModelObserver
      def onSaveModel(model)
        DeadRabbit::MopsScetchup.beim_speichern(model)
      end
    end

    class Modellwache < Sketchup::AppObserver
      def wache(model)
        return if model.nil?
        @wachen ||= {}
        return if @wachen[model.object_id]
        @wachen[model.object_id] = true
        model.add_observer(Speicherwache.new)
      end
      def onNewModel(model);  wache(model); end
      def onOpenModel(model); wache(model); end
      def expectsStartupModelNotifications; true; end
    end

    def self.zeige_modell(d)
      dlg = UI::HtmlDialog.new(
        :dialog_title => 'Was der Mops in deinem Modell sieht',
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

      zahl = ->(v) { format('%.2f', v.to_f).tr('.', ',') }
      tags = (d['tags'] || []).map { |t|
        offen = t['offen'].to_i > 0 ? "<span class=x>#{t['offen']} ohne Volumen</span>" : ''
        "<tr><td><b>#{t['tag']}</b></td><td>#{t['stueck']}</td>" \
        "<td>#{t['koerper'].to_i > 0 ? zahl.call(t['volumen_m3']) + ' m³' : '<span class=x>—</span>'}</td>" \
        "<td>#{offen}</td></tr>"
      }.join
      tag_kasten = tags.empty? ? '' : <<-T
 <h2>Mengen je Tag</h2>
 <div class=unter>Gezählt nach deinen Tags. m³ nur aus geschlossenen Volumenkörpern — offene Gruppen zähle ich, schätze sie aber nicht.</div>
 <table class=tags>
  <tr><th>Tag</th><th>Stück</th><th>Volumen</th><th></th></tr>
  #{tags}
 </table>
 <h2>Was ich aus deinen Namen lese</h2>
      T

      <<-HTML
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{font:14px -apple-system,system-ui,sans-serif;margin:0;padding:22px;
      background:#faf7f2;color:#2b2b2b}
 h2{font-size:17px;margin:4px 0 4px}
 table.tags{margin-bottom:26px;background:#fff;border-radius:12px}
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
 <h1>Was ich in deinem Modell sehe</h1>
 #{tag_kasten}
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

      # Kein zweiter Knopf mehr, nur ein Menueeintrag. Andreas am Abend des
      # 22.09.: „das plugin hat 3 knoepfe und ist auch zu kompliziert."
      # In der Leiste steht darum genau einer. Das Durchsehen bleibt
      # erreichbar — Raphael hatte danach gefragt — aber es draengt sich
      # nicht mehr auf, solange er zeichnet.
      cmd2 = UI::Command.new('Was weisst du über mein Modell?') {
        DeadRabbit::MopsScetchup.modell_durchsehen
      }
      cmd2.tooltip = 'Alle Bauteilnamen durchsehen lassen'
      cmd2.status_bar_text = 'Zeigt, was der Mops aus deinen Namen liest — und was fehlt.'
      if File.exist?(icon)
        cmd2.small_icon = icon
        cmd2.large_icon = icon
      end


      menue = UI.menu('Extensions')
      menue.add_item(cmd)
      menue.add_item(cmd2)
      schalter = menue.add_item('Mops liest beim Speichern mit') {
        m = DeadRabbit::MopsScetchup
        m.mitlesen_setzen(m.mitlesen == 'ja' ? 'nein' : 'ja')
      }
      menue.set_validation_proc(schalter) {
        DeadRabbit::MopsScetchup.mitlesen == 'ja' ? MF_CHECKED : MF_UNCHECKED
      }
      toolbar = UI::Toolbar.new('Malmops')
      toolbar.add_item(cmd)
      toolbar.show

      wache = Modellwache.new
      Sketchup.add_observer(wache)
      wache.wache(Sketchup.active_model)

      @ui_ready = true
    end

  end
end
