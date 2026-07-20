ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup"

# NOTE: the Ractor-mode rackup files (config.ru / config_ractor.ru) install
# `RactorRailsShim.install` themselves with proper boot-phase guards. Do NOT
# install the shim from boot.rb — doing so would run `install` on every
# production boot (db:prepare, assets:precompile, console, rake tasks),
# mutating Rails internals for processes that don't need it, and any
# `LoadError` from a missing gem would be silently swallowed by the bare
# `require`. If you need the shim in a non-server context, require + install
# it explicitly in that entrypoint.
