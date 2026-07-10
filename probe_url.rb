# frozen_string_literal: true
require "stringio"
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)

%i[post_path session_path].each do |which|
  Ractor.new(app, which) do |a, w|
    RactorRailsShim.init_worker_ar_connections!
    h = Rails.application.routes.url_helpers
    begin
      r = case w
          when :post_path then h.post_path(Post.first)
          when :session_path then h.session_path(:user)
          end
      [w, :ok, r[0,80]]
    rescue => ex
      root = ex; root = root.cause while root.respond_to?(:cause) && root.cause
      [w, ex.class.name, ex.message[0,120], "ROOT: #{root.class}: #{root.message[0,120]}", (root.backtrace||[]).first(10)]
    end
  end.value.tap { |r| puts r.inspect[0,400]; puts "---" }
end
