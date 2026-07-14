#!/usr/bin/env ruby
# frozen_string_literal: true
# Sustained crash reproducer for kino :ractor concurrent POST.
# Boots the app in ractor mode, signs in once, then hammers POST /posts
# with ab until a worker Bus Error / crash appears in the kino log (or
# ROUNDS rounds elapse). Reports rps per round.
require "net/http"
require "open3"
require "cgi"
require "tempfile"
require "fileutils"

PORT    = (ARGV[0] || 3377).to_i
ROUNDS  = (ENV["REPRO_ROUNDS"] || 12).to_i
DUR     = (ENV["REPRO_DUR"] || 20).to_i
CONC    = (ENV["REPRO_CONC"] || 96).to_i
APP     = File.expand_path("..", __dir__)
AB      = "/usr/sbin/ab"
DB      = "postgresql://dev@127.0.0.1:5432/full_test_app_test"
EMAIL   = "signin@test.com"
PW      = "password"
LOG     = "/tmp/kino_repro.log"

ENV2 = {
  "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "dummy", "DATABASE_URL" => DB,
  "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES",
  "KINO_MODE" => (ENV["KINO_MODE"] || "ractor"), "BENCHMARK_STATS" => "1",
  "SERVER" => (ENV["SERVER"] || ""),
  "RUBY_GC_DISABLE_COMPACTION" => (ENV["DISABLE_COMPACTION"] || "0"),
}
MODE = ENV["KINO_MODE_FLAG"] || "-m"
MODE_ARG = ENV["KINO_MODE_ARG"] || "ractor"
CMD = ["bundle", "exec", "kino", MODE, MODE_ARG, "-w", "12", "-t", "1",
       "-p", PORT.to_s, "-C", "kino.rb", "config_ractor.ru"]

def http_get(port, path, cookie: nil)
  h = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Get.new(path)
  req["Cookie"] = cookie if cookie
  h.request(req)
end

def wait_ready(port, timeout: 90)
  deadline = Time.now + timeout
  loop do
    begin
      return true if Net::HTTP.get_response("127.0.0.1", "/up", port).code == "200"
    rescue StandardError; end
    raise "not ready" if Time.now > deadline
    sleep 0.5
  end
end

def crash_markers
  File.exist?(LOG) ? File.read(LOG) : ""
end

def crashed?
  c = crash_markers
  c =~ /Bus Error|SIGBUS|signal 10|EXC_BADACCESS|ractor.*crash|wrong.*address|Segmentation|SIGSEGV/i
end

Dir.chdir(APP)
FileUtils.rm_f(LOG)
pid = spawn(ENV2, *CMD, err: LOG)
begin
  wait_ready(PORT)
  # sign in
  res1 = http_get(PORT, "/users/sign_in")
  tok1 = res1.body[/<meta name="csrf-token" content="([^"]*)"/i, 1]
  sc1 = res1["set-cookie"]&.split(";")&.first
  raise "no tok1" unless tok1
  h = Net::HTTP.new("127.0.0.1", PORT)
  req = Net::HTTP::Post.new("/users/sign_in")
  req["Cookie"] = sc1&.split(";")&.first
  req.set_form_data("user[email]" => EMAIL, "user[password]" => PW, "authenticity_token" => tok1)
  res2 = h.request(req)
  auth_cookie = (res2.get_fields("set-cookie") || []).map { |c| c.split(";").first }.find { |c| c.downcase.include?("session") }
  raise "no session" unless auth_cookie
  res3 = http_get(PORT, "/posts/new", cookie: auth_cookie)
  tok3 = res3.body[/<meta name="csrf-token" content="([^"]*)"/i, 1]
  sc3 = res3["set-cookie"]&.split(";")&.first
  cookie = sc3 || auth_cookie
  raise "no create token" unless tok3

  postdata = "authenticity_token=#{CGI.escape(tok3)}&post[title]=Repro&post[body]=Repro+body"
  tf = Tempfile.new("postdata"); tf.write(postdata); tf.flush

  # single POST sanity (must be 302)
  single = Net::HTTP.new("127.0.0.1", PORT)
  sreq = Net::HTTP::Post.new("/posts")
  sreq["Cookie"] = cookie.split(";").first
  sreq["X-CSRF-Token"] = tok3
  sreq.set_form_data("authenticity_token" => tok3, "post[title]" => "Repro", "post[body]" => "Repro")
  sres = single.request(sreq)
  puts "single POST => #{sres.code} #{sres['location'].inspect}"

  ROUNDS.times do |i|
    out = `#{AB} -c #{CONC} -t #{DUR} -k -q -r -C #{cookie.split(";").first} -H "X-CSRF-Token: #{tok3}" -T "application/x-www-form-urlencoded" -p #{tf.path} http://127.0.0.1:#{PORT}/posts 2>&1`
    rps = out[/Requests per second:\s+([\d.]+)/, 1]
    failed = out[/Failed requests:\s+(\d+)/, 1]
    if ENV["REPRO_DUMP"]
      File.write("/tmp/kino_ab_#{i + 1}.log", out)
    end
    puts "round #{i + 1}: rps=#{rps} failed=#{failed}"
    if crashed?
      puts "!!! CRASH REPRODUCED in round #{i + 1} !!!"
      puts "--- kino log tail ---"
      puts crash_markers.split("\n").last(40).join("\n")
      break
    end
  end
  puts "no crash observed after #{ROUNDS} rounds" unless crashed?
ensure
  Process.kill("KILL", pid) rescue nil
  tf&.close!
end
