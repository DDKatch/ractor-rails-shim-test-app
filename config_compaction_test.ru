# frozen_string_literal: true
# Test rackup: wraps config_ractor.ru but patches WorkerApp to enable
# GC.auto_compact = true inside each worker Ractor's setup_once!.
# Used to re-verify whether compaction still hangs kino :ractor on 0.2.5.
#
# Usage:
#   RAILS_ENV=production SECRET_KEY_BASE=dummy DATABASE_URL=... \
#   KINO_MODE=ractor \
#   bundle exec kino -m ractor -w5 -t1 -p 3399 -C kino.rb config_compaction_test.ru

# Pre-install the shim and patch WorkerApp BEFORE config_ractor.ru boots.
require "ractor_rails_shim"
RactorRailsShim.install

RactorRailsShim::WorkerApp.class_eval do
  alias_method :_orig_setup_once!, :setup_once!
  def setup_once!
    _orig_setup_once!
    GC.auto_compact = true
  end
end

# Eval config_ractor.ru in a Rack::Builder context so `run`, `use`, etc. work.
orig = File.read(File.expand_path("config_ractor.ru", __dir__))
instance_eval(orig, File.expand_path("config_ractor.ru", __dir__))