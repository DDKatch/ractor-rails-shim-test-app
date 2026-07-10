# frozen_string_literal: true
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
m = Devise.mappings.values.first
puts "mapping=#{m.class}"
%i[name to router_name singular scoped_path path path_prefix format sign_out_via modules strategies routes used_helpers controllers].each do |meth|
  begin
    v = m.public_send(meth)
    puts "#{meth}=#{v.inspect[0,50]}"
  rescue => e
    puts "#{meth} ERR #{e.class}: #{e.message[0,80]}"
  end
end
begin
  s = RactorRailsShim.send(:_devise_mapping_snapshot, m)
  puts "SNAP=#{s.inspect[0,60]}"
rescue => e
  puts "SNAP ERR #{e.class}: #{e.message[0,120]}"
  puts e.backtrace.first(6).join("\n")
end

s = RactorRailsShim.send(:_devise_mapping_snapshot, m)
puts "SNAP name=#{s.name.inspect} class=#{s.class}"
puts "resource_name sym => #{:"@#{s.name}"}.inspect"
