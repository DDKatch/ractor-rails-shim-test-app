require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FullTestApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Rails 8.1 defaults the Active Storage variant processor to :vips, which
    # needs the libvips native library. This dev box has ImageMagick but not
    # libvips, so pin the processor to :mini_magick to avoid the
    # "requires the libvips library" boot warning (and keep variant generation
    # working for attached avatars).
    config.active_storage.variant_processor = :mini_magick

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Mailer previews (RAILS_FEATURES.md #32): serve the previews from
    # test/mailers/previews via the built-in /rails/mailers engine (dev only).
    config.action_mailer.preview_paths << Rails.root.join("test/mailers/previews")

    # Console helpers (RAILS_FEATURES.md #59): include ConsoleHelpers into the
    # top level of every `bin/rails console` session, so `app_stats`,
    # `make_user`, and `make_post` are callable from the prompt.
    console do
      Object.send(:include, ConsoleHelpers)
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Berlin"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
