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

Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  m = Devise.mappings[:user] rescue nil
  puts "mapping: #{m.inspect[0,400]}"
  puts "mappings shareable? #{Ractor.shareable?(Devise.mappings)}"
  if m
    m.instance_variables.each do |iv|
      v = m.instance_variable_get(iv)
      if v.is_a?(Proc)
        puts "PROC ivar #{iv}: defined in #{v.send(:ractor)? 'ractor?' : '?'}"
      end
    end
  end
  # Check resource_class / resource_name helpers via a fake controller context is hard;
  # instead inspect Devise::Mapping#respond_to? and format
  puts "format: #{m.format.inspect}" rescue puts "no format"
  [:controllers, :path_names, :sign_out_via, :failure_app, :default_scope, :used_helpers, :modules, :routers, :path].each do |k|
    begin
      v = m.send(k)
      puts "#{k}: #{v.class} #{v.inspect[0,120]}"
    rescue => e
      puts "#{k}: ERR #{e.class}"
    end
  end
  "done"
end.value
