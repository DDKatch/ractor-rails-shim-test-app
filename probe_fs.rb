# frozen_string_literal: true
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require_relative "config/environment"
app = Rails.application
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)

res = Ractor.new(app) do |a|
  g = "/Users/dev/.asdf/installs/ruby/4.0.5/lib/ruby/gems/4.0.0/gems/devise-5.0.4/app/views"
  [
    Dir.glob(g + "/devise/sessions*"),
    File.exist?(g + "/devise/sessions/new.html.erb"),
  ]
end.value
puts "AFTER RAILS BOOT ractor glob: #{res.inspect}"

# Also test a bare ractor (no rails) for comparison
r2 = Ractor.new { Dir.glob("/Users/dev/.asdf/installs/ruby/4.0.5/lib/ruby/gems/4.0.0/gems/devise-5.0.4/app/views/devise/sessions*") }
puts "BARE ractor glob: #{r2.value.inspect}"
