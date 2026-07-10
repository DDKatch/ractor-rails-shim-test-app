ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup"

# Install the shim only in production — Ractor mode requires it.
# In development, the shim's callback routing interferes with Devise.
if ENV["RAILS_ENV"] == "production"
  require "ractor_rails_shim"
  RactorRailsShim.install
end
