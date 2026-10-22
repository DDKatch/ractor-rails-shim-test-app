# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "audit_engine"
  spec.version = "0.1.0"
  spec.authors = ["ractor-rails-shim-test-app"]
  spec.summary = "Minimal isolated engine for the RAILS_FEATURES.md #144 audit"
  spec.required_ruby_version = ">= 4.0.6"
  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "app/views/**/*", "config/routes.rb"]
  spec.require_paths = ["lib"]
end
