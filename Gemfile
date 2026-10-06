source "https://rubygems.org"

# Git source: CI + Dependabot resolve it (a local `path:` gem broke both).
# For local development point bundler at the working copy instead of the
# pushed branch (keeps unpushed shim changes visible):
#   bundle config set --local local.ractor-rails-shim ../ractor-rails-shim
# Cut a release and revert to `gem "ractor-rails-shim", "~> 0.4"` before
# publishing the test-app repo.
gem "ractor-rails-shim", github: "DDKatch/ractor-rails-shim", branch: "main"
gem "rails", "~> 8.1.3"
gem "propshaft"
gem "tailwindcss-rails"
gem "pg", "~> 1.7"
gem "puma", ">= 5.0"
gem "falcon"
# Pin kino: the README requires the official kino 0.2.x gem; an unbounded
# `gem "kino"` would happily pull a future 0.3 with breaking API changes.
gem "kino", "~> 0.2.1"
gem "devise", ">= 4.9"
gem "kaminari", "~> 1.2"
# ActiveStorage variant generation needs image_processing; without it Rails
# warns on every boot ("Generating image variants require the image_processing
# gem"). The app attaches avatars, so keep the transformer available.
gem "image_processing", "~> 1.2"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "msgpack", ">= 1.7.0"
# csv left the stdlib in Ruby 3.4 — the report mailer + downloads CSV need it.
gem "solid_cache"
gem "solid_queue" # Rails 8 default database-backed job queue # Rails 8 default database-backed cache store
gem "solid_cable" # Rails 8 default database-backed Action Cable pubsub (no redis dependency)

gem "csv"

# Production boot helpers expected by the default Rails 8 Dockerfile
# (`bundle exec bootsnap precompile` and `bin/thrust`). Bootsnap speeds up
# boot; Thruster is the production HTTP/2 proxy in front of `bin/rails server`.
group :production do
  gem "bootsnap", require: false
  gem "thruster", require: false
end

group :development, :test do
  # System tests (RAILS_FEATURES.md #56): capybara drives the :rack_test
  # driver (no browser needed); selenium-webdriver is preinstalled for
  # future JS-driven system tests.
  gem "capybara"
  gem "selenium-webdriver"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rubocop-rails-omakase"
  gem "brakeman", "~> 8.1"
  gem "bundler-audit"
  gem "stackprof"
end
