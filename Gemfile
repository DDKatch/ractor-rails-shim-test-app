source "https://rubygems.org"

gem "ractor-rails-shim", "~> 0.2"
gem "rails", "~> 8.1.3"
gem "propshaft"
gem "tailwindcss-rails"
gem "pg", "~> 1.4"
gem "puma", ">= 5.0"
gem "falcon"
# Pin kino: the README requires the official kino 0.1.x gem; an unbounded
# `gem "kino"` would happily pull a future 0.2 with breaking API changes.
gem "kino", "~> 0.2.0"
gem "devise", ">= 4.9"
gem "kaminari", "~> 1.2"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "msgpack", ">= 1.7.0"

# Production boot helpers expected by the default Rails 8 Dockerfile
# (`bundle exec bootsnap precompile` and `bin/thrust`). Bootsnap speeds up
# boot; Thruster is the production HTTP/2 proxy in front of `bin/rails server`.
group :production do
  gem "bootsnap", require: false
  gem "thruster", require: false
end

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rubocop-rails-omakase"
  gem "brakeman"
  gem "bundler-audit"
  gem "stackprof"
end
