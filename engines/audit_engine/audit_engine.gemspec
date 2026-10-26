# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "audit_engine"
  spec.version = "0.1.0"
  spec.authors = [ "ractor-rails-shim-test-app" ]
  spec.summary = "Minimal isolated engine for the RAILS_FEATURES.md #144 audit"
  # JRuby 10.1.2.0 reports Ruby 4.0.0; the engine uses no 4.0.6+ features.
  spec.required_ruby_version = ">= 4.0"
  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "app/views/**/*", "config/routes.rb"]
  spec.require_paths = [ "lib" ]
end
