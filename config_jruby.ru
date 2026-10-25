# frozen_string_literal: true

# Plain Rails boot for the JRuby benchmark (the Reddit-comment comparison:
# "fully parallel shared memory concurrency in Rails today ... on JRuby").
#
# No ractor-rails-shim here. The shim exists for YARV 4.0.x:
#   * the Ractor-isolation fixes are meaningless on JRuby (no Ractors), and
#   * the Ruby 4.0.5 class_attribute / __callbacks corruption it patches is a
#     YARV-era bug — JRuby's shared-heap, JIT execution doesn't have it.
# Under JRuby the app runs as stock Rails: shared heap, real OS threads,
# Puma's thread pool does the concurrency.

ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "production"

require "bundler/setup"
# Register the JDBC postgres adapter (no activerecord-jdbcpostgresql-adapter
# sub-gem: its releases lag the core arjdbc 81.0.pre1 we pin in Gemfile.jruby).
require "arjdbc/postgresql"

require_relative "config/application"

# Workaround for a thread-safety bug in json 3.1.0-java: JSON::Coder#dump reuses
# one frozen GeneratorState across threads; concurrent dumps corrupt its nesting
# depth counter => JSON::NestingError ("nesting of 101 is too deep") on every
# session-cookie commit under load (reproduced standalone, 20/20 threads).
# MRI's json ext is per-call-state and unaffected. Synchronize the dump around
# a per-coder mutex — session cookies are tiny, so the lock is negligible.
require "json"
module SafeJsonCoderDump
  def dump(object, io = nil)
    @dump_mutex ||= Mutex.new
    @dump_mutex.synchronize { super }
  end
end
JSON::Coder.prepend(SafeJsonCoderDump)

require_relative "config/environment"

run Rails.application
