# mops_scetchup.rb
# Loader für die "Malmops"-SketchUp-Extension (Bogen 4).
# Kommt in den SketchUp Plugins-Ordner (oder per Symlink aus diesem Repo, siehe README).
#
# Der Loader registriert die Extension; der eigentliche Code liegt in mops_scetchup/main.rb.

require 'sketchup.rb'
require 'extensions.rb'

module DeadRabbit
  module MopsScetchup

    PLUGIN_ID   = 'mops_scetchup'.freeze
    PLUGIN_NAME = 'Malmops'.freeze
    PLUGIN_ROOT = File.dirname(__FILE__).freeze

    unless defined?(@loaded) && @loaded
      loader = File.join(PLUGIN_ROOT, PLUGIN_ID, 'main')
      extension = SketchupExtension.new(PLUGIN_NAME, loader)
      extension.description = 'Fragt den Mops zu einem markierten Bauteil und schreibt die ' \
                             'LV-Info (Baustein, Aufwandswert, Preis) als Attribut ans Bauteil. Spike.'
      extension.version = '0.1.0'
      extension.creator = 'Dead Rabbit / iMOPS'
      extension.copyright = '© 2026 Andreas Pelczer'
      Sketchup.register_extension(extension, true)
      @loaded = true
    end

  end
end
