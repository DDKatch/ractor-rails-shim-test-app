# RAILS_FEATURES.md #128: preload the custom encrypted disk service at boot
# (initializers run before the service Configurator's require in any request
# path, and before Zeitwerk eager-load — lib/ is not an autoload dir).
# DiskService (the base class) autoloads lazily, so require it first.
require "active_storage/service/disk_service"
require "active_storage/service/encrypted_disk_service"
