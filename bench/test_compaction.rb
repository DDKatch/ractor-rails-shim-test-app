#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-verify whether GC.auto_compact = true hangs kino :ractor under load.
# Boots the app with compaction enabled in each worker Ractor, then runs ab.
require "net/http"
require "open3"

PORT = (ARGV[0] || 3399).to_i
DUR  = (ENV["TEST_DUR"] || 30).to_i
CONC = (ENV["TEST_CONC"] || 64).to_i
APP  = File.expand_path("..", __dir__)
AB   = "/usr/sbin/ab"
DB   = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
LOG  = "/tmp/kino_compaction_test.log"

ENV2 = {
  "RAILS_ENV" => "production",
  "SECRET_KEY_BASE" => "dummy",
  "DATABASE_URL" => DB,
  "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES",
  "KINO_MODE" => "ractor",
  "BENCHMARK_STATS" => "1",
  "RUBY_GC_DISABLE_COMPACTION" => "0"
}

# Patch WorkerApp to enable compaction in each worker, then load the rackup.
# We use a custom rackup that wraps config_ractor.ru.
RACKUP = File.expand_path("config_compaction_test.ru", APP)
CMD = [ "bundle", "exec", "kino", "-m", "ractor", "-w", "5", "-t", "1",
       "-p", PORT.to_s, "-C", "kino.rb", RACKUP ]

def wait_ready(port, timeout: 90)
  deadline = Time.now + timeout
  loop do
    begin
      r = Net::HTTP.get_response("127.0.0.1", "/up", port)
      return true if r.code == "200"
    rescue StandardError; end
    raise "server not ready within #{timeout}s" if Time.now > deadline
    sleep 0.5
  end
end

def check_alive(port)
  begin
    r = Net::HTTP.get_response("127.0.0.1", "/up", port)
    r.code == "200"
  rescue StandardError
    false
  end
end

Dir.chdir(APP)
File.delete(LOG) if File.exist?(LOG)

puts "Booting kino :ractor with GC.auto_compact = true (per-worker)..."
puts "CMD: #{CMD.join(' ')}"
pid = spawn(ENV2, *CMD, err: LOG, out: LOG)
puts "PID: #{pid}, log: #{LOG}"

begin
  wait_ready(PORT)
  puts "Server ready. Warming up 5s..."
  sleep 5

  puts "Checking server still alive after warmup..."
  if check_alive(PORT)
    puts "ALIVE. Running ab -c #{CONC} -t #{DUR} -k against /up..."
  else
    puts "DEAD after warmup. Checking log..."
    puts File.read(LOG).split("\n").last(30).join("\n")
    exit 1
  end

  out = `#{AB} -c #{CONC} -t #{DUR} -k -q http://127.0.0.1:#{PORT}/up 2>&1`
  rps = out[/Requests per second:\s+([\d.]+)/, 1]
  failed = out[/Failed requests:\s+(\d+)/, 1]
  complete = out[/Complete requests:\s+(\d+)/, 1]
  puts "ab /up: rps=#{rps} failed=#{failed} complete=#{complete}"

  if check_alive(PORT)
    puts "ALIVE after /up load. Running ab against /posts..."
    out2 = `#{AB} -c #{CONC} -t #{DUR} -k -q http://127.0.0.1:#{PORT}/posts 2>&1`
    rps2 = out2[/Requests per second:\s+([\d.]+)/, 1]
    failed2 = out2[/Failed requests:\s+(\d+)/, 1]
    complete2 = out2[/Complete requests:\s+(\d+)/, 1]
    puts "ab /posts: rps=#{rps2} failed=#{failed2} complete=#{complete2}"

    if check_alive(PORT)
      puts "ALIVE after /posts load."
      puts "RESULT: GC.auto_compact = true does NOT hang. Compaction is safe on 0.2.5."
    else
      puts "DEAD after /posts load. Compaction hangs under DB read pressure."
      puts File.read(LOG).split("\n").last(30).join("\n")
    end
  else
    puts "DEAD after /up load. Compaction hangs under /up pressure."
    puts File.read(LOG).split("\n").last(30).join("\n")
  end
ensure
  Process.kill("KILL", pid) rescue nil
  Process.wait(pid) rescue nil
end
