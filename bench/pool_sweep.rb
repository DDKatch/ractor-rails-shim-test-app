#!/usr/bin/env ruby
# frozen_string_literal: true
#
# DB-pool sweep for kino :ractor — isolates the pool-size variable.
#
# Thesis: GET /posts's ~8x lag vs forked servers is a pool-size confound
# (5 ractors x 1 conn vs 5 procs x 5 conns = 25). Bumping the per-Ractor pool
# to 5 (-> 25 total) should close most of the gap on the read path.
#
# Boots kino via a shell-backgrounded `bundle exec kino` (Ruby's `spawn` makes
# kino's native listener drop its port under a non-interactive parent; the
# shell `&` form works reliably), then drives `ab` from Ruby.
#
# Run:  cd ractor-rails-shim-test-app && ruby bench/pool_sweep.rb
# Env:  BENCH_DURATION=15 BENCH_WARMUP=5 BENCH_RUNS=2
#       POOLS="1,5,25" TOPOLOGIES="w5t1,w5t5" PORT=3500

require "net/http"
require "socket"
require "json"
require "fileutils"
require "tempfile"
require "cgi"
require "shellwords"

APP_DIR     = File.expand_path("..", __dir__)
PORT        = (ENV["PORT"] || 3500).to_i
AB          = "/usr/sbin/ab"
DURATION    = (ENV["BENCH_DURATION"] || 15).to_i
WARMUP      = (ENV["BENCH_WARMUP"] || 5).to_i
RUNS        = (ENV["BENCH_RUNS"] || 2).to_i
POOLS       = (ENV["POOLS"] || "1,5,25").split(",").map(&:to_i)
TOPOS       = (ENV["TOPOLOGIES"] || "w5t1,w5t5").split(",")
USER_EMAIL  = "signin@test.com"
USER_PW     = "password"
BASE_DB_URL = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"

# --- helpers ---------------------------------------------------------------
def listening_pids(port)
  `lsof -nP -Fp -iTCP:#{port} -sTCP:LISTEN 2>/dev/null`.scan(/^p(\d+)/).flatten.map(&:to_i).uniq
end

def cleanup_port(port)
  listening_pids(port).each { |v| Process.kill("KILL", v) rescue nil }
  sleep 1
end

def wait_ready(port, timeout = 90)
  deadline = Time.now + timeout
  loop do
    begin
      return true if Net::HTTP.get_response("127.0.0.1", "/up", port).code == "200"
    rescue StandardError
    end
    raise "server on :#{port} not ready after #{timeout}s" if Time.now > deadline
    sleep 0.5
  end
end

def boot_kino_shell(topology, pool, port)
  # topology is like "w5t1" or "w5t5": workers after 'w', threads after 't'.
  m = topology.match(/w(\d+)t(\d+)/) or raise "bad topology #{topology.inspect}"
  workers, threads = m[1].to_i, m[2].to_i
  db_url = "#{BASE_DB_URL}?pool=#{pool}"
  env = ENV.to_h.merge(
    "DATABASE_URL" => db_url,
    "RAILS_ENV" => "production",
    "SECRET_KEY_BASE" => "dummy",
    "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES",
    "KINO_MODE" => "ractor",
    "BENCHMARK_STATS" => "1",
    "RUBY_GC_DISABLE_COMPACTION" => "1",
  )
  cmd = ["bundle", "exec", "kino", "-m", "ractor",
         "-w", workers.to_s, "-t", threads.to_s, "-p", port.to_s,
         "-C", "kino.rb", "config_ractor.ru"]
  log = "/tmp/kino_pool_#{topology}-pool#{pool}.log"
  # kino drains on stdin EOF; under a non-interactive parent the inherited
  # stdin is already EOF, so hold a pipe open as kino's stdin and keep the
  # write end alive until teardown (closing it drains kino gracefully).
  stdin_r, stdin_w = IO.pipe
  pid = spawn(env, *cmd, chdir: Dir.pwd, in: stdin_r, out: log, err: "#{log}.err")
  stdin_r.close
  $kino_stdin_hold = stdin_w  # pin so GC never closes it mid-run
  wait_ready(port)
  { pid: pid, stdin: stdin_w }
end

def parse_ab(out)
  {
    rps:    out[/Requests per second:\s+([\d.]+)/, 1]&.to_f,
    failed: out[/Failed requests:\s+(\d+)/, 1]&.to_i,
    non2xx: out[/Non-2xx responses:\s+(\d+)/, 1]&.to_i,
    p50:    out[/^\s*50%\s+([\d.]+)/, 1]&.to_f,
    p95:    out[/^\s*95%\s+([\d.]+)/, 1]&.to_f,
    p99:    out[/^\s*99%\s+([\d.]+)/, 1]&.to_f,
  }
end

def median(xs)
  s = xs.compact.sort
  return nil if s.empty?
  (s[(s.length - 1) / 2] + s[s.length / 2]) / 2.0
end

def run_ab(port, path, method: :get, cookie: nil, postfile: nil, csrf: nil)
  cmd = [AB, "-c", "64", "-t", DURATION.to_s, "-k", "-q", "-r"]
  cmd += ["-C", cookie] if cookie
  cmd += ["-H", "X-CSRF-Token: #{csrf}"] if csrf
  cmd += ["-T", "application/x-www-form-urlencoded", "-p", postfile] if method == :post
  cmd += ["http://127.0.0.1:#{port}#{path}"]
  parse_ab(`#{cmd.shelljoin} 2>&1`)
end

def warmup(port, path)
  system([AB, "-c", "64", "-t", WARMUP.to_s, "-k", "-q", "-r",
          "http://127.0.0.1:#{port}#{path}"].shelljoin,
         out: "/dev/null", err: "/dev/null")
rescue StandardError
end

def cookie_val(h) = h&.split(";")&.first&.strip

def session_cookie(res)
  cks = res.get_fields("set-cookie") || [res["set-cookie"]].compact
  cks.map { |c| c.split(";").first.strip }
     .find { |c| c.downcase.include?("session") } || cks.map { |c| c.split(";").first.strip }.first
end

def get_token(port, path, cookie: nil)
  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Get.new(path)
  req["Cookie"] = cookie if cookie
  res = http.request(req)
  body = res.body.to_s
  token = body[/<meta name="csrf-token" content="([^"]*)"/i, 1] ||
          body[/name="authenticity_token"[^>]*value="([^"]*)"/, 1]
  [token, session_cookie(res)]
end

def sign_in(port)
  tok, ck = get_token(port, "/users/sign_in")
  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Post.new("/users/sign_in")
  req["Cookie"] = cookie_val(ck)
  req["X-CSRF-Token"] = tok
  req.set_form_data("user[email]" => USER_EMAIL, "user[password]" => USER_PW,
                    "authenticity_token" => tok)
  res = http.request(req)
  raise "sign-in failed: #{res.code}" unless res.code =~ /^3\d\d$|^200$/
  tok, ck = get_token(port, "/posts/new", cookie: cookie_val(res["set-cookie"]))
  [cookie_val(ck), tok]
end

def verify_post(port, cookie, token)
  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Post.new("/posts")
  req["Cookie"] = cookie_val(cookie)
  req["X-CSRF-Token"] = token
  req.set_form_data("authenticity_token" => token,
                   "post[title]" => "Sweep", "post[body]" => "s")
  res = http.request(req)
  raise "POST verify failed: code=#{res.code} loc=#{res['location'].inspect}" unless res.code == "302" && res["location"] =~ %r{/posts/\d+\z}
end

def write_postfile(token)
  f = Tempfile.new(["post", ".txt"])
  f.write("authenticity_token=#{CGI.escape(token)}&post[title]=P&post[body]=b")
  f.close
  f.path
end

def agg(runs)
  {
    rps: median(runs.map { |r| r[:rps] })&.round,
    failed: runs.map { |r| r[:failed].to_i }.sum,
    non2xx: runs.map { |r| r[:non2xx].to_i }.sum,
    p50: median(runs.map { |r| r[:p50] }),
    p95: median(runs.map { |r| r[:p95] }),
    p99: median(runs.map { |r| r[:p99] }),
  }
end

def measure(port, cookie, token)
  warmup(port, "/up")
  warmup(port, "/posts")
  postfile = write_postfile(token)
  3.times { verify_post(port, cookie, token) }
  {
    up:    agg(RUNS.times.map { run_ab(port, "/up") }),
    posts: agg(RUNS.times.map { run_ab(port, "/posts") }),
    post:  agg(RUNS.times.map { run_ab(port, "/posts", method: :post,
                                       cookie: cookie_val(cookie), csrf: token, postfile: postfile) }),
  }
end

# --- main -----------------------------------------------------------------
puts "=" * 78
puts "kino :ractor DB-pool sweep  (shell-booted)"
puts "ruby=#{RUBY_VERSION}  cores=#{require 'etc'; Etc.nprocessors}  ab=#{`#{AB} -V 2>&1`[/[\d.]+/]}"
puts "duration=#{DURATION}s  warmup=#{WARMUP}s  runs=#{RUNS}  concurrency=64"
puts "pools=#{POOLS.inspect}  topologies=#{TOPOS.inspect}  port=#{PORT}"
puts "=" * 78

results = []
TOPOS.each do |topo|
  POOLS.each do |pool|
    label = "kino :ractor #{topo} pool=#{pool}"
    puts "\n[#{label}] booting..."
    cleanup_port(PORT)
    pid = nil
    boot = nil
    begin
      boot = boot_kino_shell(topo, pool, PORT)
      pid = boot[:pid]
      cookie, token = sign_in(PORT)
      verify_post(PORT, cookie, token)
      m = measure(PORT, cookie, token)
      results << (row = { topo: topo, pool: pool, **m })
      printf "  %-22s up=%6d rps  GET /posts=%6d rps  POST=%6d rps\n",
             label, m[:up][:rps], m[:posts][:rps], m[:post][:rps]
      printf "  %-22s p95: up=%5.0fms get=%5.0fms post=%5.0fms  (fails=%d non2xx=%d)\n",
             "", m[:up][:p95], m[:posts][:p95], m[:post][:p95],
             m[:up][:failed] + m[:posts][:failed] + m[:post][:failed],
             m[:up][:non2xx] + m[:posts][:non2xx] + m[:post][:non2xx]
    rescue StandardError => e
      puts "  ERROR: #{e.message}"
      log = "/tmp/kino_pool_#{topo}-pool#{pool}.log"
      puts "  (logs: #{log} / #{log}.err)"
    ensure
      if boot
        boot[:stdin].close rescue nil
        Process.kill("TERM", pid) rescue nil
        Process.wait(pid) rescue nil
      end
      cleanup_port(PORT)
    end
  end
end

puts "\n" + "=" * 78
puts "SUMMARY (rps)"
printf "  %-10s | %6s | %10s | %10s | %10s\n", "topo", "pool", "/up", "GET /posts", "POST"
puts "  " + "-" * 56
results.each do |r|
  up   = r[:up]&.fetch(:rps)
  posts = r[:posts]&.fetch(:rps)
  post = r[:post]&.fetch(:rps)
  if up.nil? || posts.nil? || post.nil?
    printf "  %-10s | %6d | %10s | %10s | %10s\n", r[:topo], r[:pool], up, posts, post
  else
    printf "  %-10s | %6d | %10d | %10d | %10d\n", r[:topo], r[:pool], up, posts, post
  end
end

out = File.join(APP_DIR, "bench/results/pool-sweep-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(results))
puts "\nResults written to #{out}"