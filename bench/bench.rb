#!/usr/bin/env ruby
# frozen_string_literal: true

require "shellwords"
require "net/http"
require "socket"
# Benchmark harness: compare kino :ractor vs Puma vs Falcon.
#
# For each server it boots the ractor-rails-shim-test-app, warms up, then runs `ab`
# (ApacheBench) against three endpoints:
#   /up            GET, no DB        (server/dispatch overhead)
#   /posts         GET, DB + render  (realistic read path)
#   POST /posts    DB write + 302    (write path; requires signed-in session)
#
# Two framings (user chose "both"):
#   A) single memory space, 12 concurrent units, 1 process:
#        kino -w12 (Ractors share ONE frozen graph)  [A == B for kino]
#        puma  -w0 -t12  (single process, 12 threads, 1 GVL)
#        falcon async (-n1)  (single process, async fibers -- no shim)
#        falcon --threaded (single process, async -- BROKEN on macOS)
#   B) multi-process max throughput:
#        kino -w12            (inherently single process; covers both)
#        puma  -w12 -t1       (12 worker processes)
#        falcon --forked -n12 (12 forks)
#
# Metrics per (server, endpoint): requests/sec, p50/p95/p99 latency (ms),
# and steady-state RSS (KB) of the server process tree.
#
# Run from ractor-rails-shim-test-app/:  ruby bench/bench.rb

require "open3"
require "cgi"
require "etc"
require "tmpdir"
require "tempfile"
require "fileutils"
require "json"

APP_DIR   = File.expand_path("..", __dir__)
PORT      = (ARGV[0] || 3230).to_i
AB        = "/usr/sbin/ab"
DURATION  = (ENV["BENCH_DURATION"] || 15).to_i
CONCURRENCY = (ENV["BENCH_CONCURRENCY"] || 64).to_i
NPROC     = Etc.nprocessors
DB_URL    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
USER_EMAIL = "signin@test.com"
USER_PW    = "password"

RUNS            = (ENV["BENCH_RUNS"] || 3).to_i        # repeated measurements per endpoint
WARMUP_DURATION = (ENV["BENCH_WARMUP"] || 5).to_i      # warmup ab burst (s) per endpoint
RESULTS_DIR     = File.expand_path("../bench/results", __dir__)

COMMON_ENV = {
  "RAILS_ENV" => "production",
  "SECRET_KEY_BASE" => "dummy",
  "DATABASE_URL" => DB_URL,
  # macOS aborts a forked child that touches Objective-C (e.g. via the pg gem).
  # Puma clustered / Falcon forked fork workers, so without this they crash
  # under load. Linux doesn't have this restriction.
  "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES",
}

# --- scenario definitions -------------------------------------------------
# 5-scale matrix (override with BENCH_WORKERS / BENCH_THREADS, both default 5):
#   A) single process, multi-threaded:  THREADS threads, 1 process
#   B) multi-worker:                   WORKERS workers x 1 thread
#   B) multi-worker + multi-threaded:  WORKERS workers x THREADS threads (5x5)
WORKERS = (ENV["BENCH_WORKERS"] || 5).to_i
THREADS = (ENV["BENCH_THREADS"] || 5).to_i

SCENARIOS = [
  # --- A) single process, multi-threaded (THREADS threads) ---------------
  {
    name: "kino :threaded (-t#{THREADS})",
    framing: "A",
    pgrep: "kino",
    cmd: ["bundle", "exec", "kino", "-m", "threaded", "-w", "1", "-t", THREADS.to_s,
          "-p", PORT.to_s, "-C", "kino.rb", "config_ractor.ru"],
    # kino :threaded runs plain threads in the main process (Puma/Falcon-
    # threaded equivalent), so it needs the shim's MINIMAL install. The shim
    # keys off SERVER=puma|falcon|thin|webrick|thread; without it it applies
    # its full Ractor-oriented install, which breaks Devise + the Rails
    # reloader under kino threaded (every request 500s). kino :ractor keeps
    # the full install (no SERVER set).
    env: COMMON_ENV.merge("KINO_MODE" => "threaded", "BENCHMARK_STATS" => "1",
                           "SERVER" => "thread"),
  },
  {
    name: "puma single (-w0 -t#{THREADS})",
    framing: "A",
    pgrep: "puma",
    cmd: ["bundle", "exec", "puma", "config.ru", "-p", PORT.to_s],
    env: COMMON_ENV.merge("SERVER" => "puma", "WEB_CONCURRENCY" => "0",
                           "RAILS_MAX_THREADS" => THREADS.to_s, "PORT" => PORT.to_s),
  },
  {
    name: "falcon async (-n1)",
    framing: "A",
    pgrep: "falcon",
    cmd: ["bundle", "exec", "falcon", "serve", "--forked", "-n", "1",
          "-b", "http://127.0.0.1:#{PORT}", "-c", "config.ru"],
    env: COMMON_ENV.merge("SERVER" => "falcon"),
  },
  # --- B) multi-worker (WORKERS workers x 1 thread) ----------------------
  {
    name: "kino :ractor (-w#{WORKERS} -t1)",
    framing: "B",
    pgrep: "kino",
    cmd: ["bundle", "exec", "kino", "-m", "ractor", "-w", WORKERS.to_s, "-t", "1",
          "-p", PORT.to_s, "-C", "kino.rb", "config_ractor.ru"],
    # GC compaction: Ruby's default is GC.auto_compact == false (4.0.6), so kino
    # :ractor does NOT auto-compact during the benchmark. RUBY_GC_DISABLE_COMPACTION=0
    # only refrains from disabling compaction; it does NOT switch it on. Forcing
    # GC.auto_compact=true on stock 4.0.6 was observed to hang kino :ractor under
    # sustained load (frozen shared Ractor graph corruption), so the config no longer
    # sets it. DISABLE_COMPACTION=1 makes the no-compaction stance explicit (no-op
    # under the default since compaction is already off).
    env: COMMON_ENV.merge("KINO_MODE" => "ractor", "BENCHMARK_STATS" => "1",
                           "RUBY_GC_DISABLE_COMPACTION" => (ENV["DISABLE_COMPACTION"] ? "1" : "0")),
  },
  {
    name: "puma clustered (-w#{WORKERS} -t1)",
    framing: "B",
    pgrep: "puma",
    cmd: ["bundle", "exec", "puma", "config.ru", "-p", PORT.to_s],
    env: COMMON_ENV.merge("SERVER" => "puma", "WEB_CONCURRENCY" => WORKERS.to_s,
                           "RAILS_MAX_THREADS" => "1", "PORT" => PORT.to_s),
  },
  {
    name: "falcon forked (-n#{WORKERS})",
    framing: "B",
    pgrep: "falcon",
    cmd: ["bundle", "exec", "falcon", "serve", "--forked", "-n", WORKERS.to_s,
          "-b", "http://127.0.0.1:#{PORT}", "-c", "config.ru"],
    env: COMMON_ENV.merge("SERVER" => "falcon"),
  },
  # --- B) multi-worker + multi-threaded (WORKERS x THREADS = 5x5) --------
  {
    name: "kino :ractor (-w#{WORKERS} -t#{THREADS})",
    framing: "B",
    pgrep: "kino",
    cmd: ["bundle", "exec", "kino", "-m", "ractor", "-w", WORKERS.to_s, "-t", THREADS.to_s,
          "-p", PORT.to_s, "-C", "kino.rb", "config_ractor.ru"],
    env: COMMON_ENV.merge("KINO_MODE" => "ractor", "BENCHMARK_STATS" => "1",
                           "RUBY_GC_DISABLE_COMPACTION" => (ENV["DISABLE_COMPACTION"] ? "1" : "0")),
  },
  {
    name: "puma clustered (-w#{WORKERS} -t#{THREADS})",
    framing: "B",
    pgrep: "puma",
    cmd: ["bundle", "exec", "puma", "config.ru", "-p", PORT.to_s],
    env: COMMON_ENV.merge("SERVER" => "puma", "WEB_CONCURRENCY" => WORKERS.to_s,
                           "RAILS_MAX_THREADS" => THREADS.to_s, "PORT" => PORT.to_s),
  },
  {
    name: "falcon hybrid (-n#{WORKERS} --threads #{THREADS})",
    framing: "B",
    pgrep: "falcon",
    cmd: ["bundle", "exec", "falcon", "serve", "--hybrid", "-n", WORKERS.to_s,
          "--threads", THREADS.to_s,
          "-b", "http://127.0.0.1:#{PORT}", "-c", "config.ru"],
    env: COMMON_ENV.merge("SERVER" => "falcon"),
    wait_timeout: 25,
  },
]

if (filter = ENV["BENCH_SCENARIO"])
  SCENARIOS.select! { |s| s[:name].downcase.include?(filter.downcase) }
  raise "no scenarios matched BENCH_SCENARIO=#{filter.inspect}" if SCENARIOS.empty?
end

# --- helpers ---------------------------------------------------------------
def sh(*cmd)
  system(*cmd)
end

def wait_ready(port, timeout: 90)
  deadline = Time.now + timeout
  loop do
    begin
      res = Net::HTTP.get_response("127.0.0.1", "/up", port)
      return true if res.code == "200"
    rescue StandardError
    end
    raise "server on :#{port} not ready after #{timeout}s" if Time.now > deadline
    sleep 0.5
  end
end

def wait_port_free(port, timeout: 30)
  deadline = Time.now + timeout
  loop do
    begin
      TCPSocket.new("127.0.0.1", port).close
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return true
    end
    raise "port :#{port} still bound after #{timeout}s" if Time.now > deadline
    sleep 0.5
  end
end

# PIDs actually listening on +port+ (catches forked workers regardless of
# cmdline or parent — e.g. Falcon's forked children aren't matched by pgrep).
def listening_pids(port)
  out = `lsof -nP -Fp -iTCP:#{port} -sTCP:LISTEN 2>/dev/null`
  out.scan(/^p(\d+)/).flatten.map(&:to_i).uniq
end

# Kill anything currently LISTENing on +port+ (catches stale servers whose
# process title was renamed away from the pgrep pattern).
def cleanup_port(port)
  listening_pids(port).each { |v| Process.kill("KILL", v) rescue nil }
  sleep 1
end

# All PIDs in the process tree rooted at +root_pid+ (parent→child walk).
def descendant_pids(root_pid)
  snap = `ps -ax -o pid=,ppid=`.lines.map { |l| l.split.map(&:to_i) }
  children = Hash.new { |h, k| h[k] = [] }
  snap.each { |pid, ppid| children[ppid] << pid if pid && ppid }
  seen, stack = [], [root_pid]
  while stack.any?
    p = stack.pop
    next if seen.include?(p) || p.zero?
    seen << p
    stack.concat(children[p])
  end
  seen
end

# Every PID that makes up the running server (listeners + the boot tree),
# deduplicated. This is what we sum for memory.
def server_pids(port, root_pid)
  (listening_pids(port) + descendant_pids(root_pid)).uniq.reject(&:zero?)
end

def rss_of(pids)
  return 0 if pids.empty?
  `ps -o rss= -p #{pids.join(",")}`.lines.map(&:to_i).sum
end

# COW-aware unique memory (macOS `footprint` "Physical footprint", which
# already accounts for shared pages). Returns total bytes, or nil if unavailable
# (caller falls back to rss_of). Each worker is sampled independently.
def footprint_of(pids)
  return nil if pids.empty?
  total = 0
  pids.each do |pid|
    out = `footprint -p #{pid} 2>/dev/null`
    m = out.match(/footprint:\s*([\d.]+)\s*([KMG])?B/i)
    return nil unless m
    val = m[1].to_f
    val *= 1024 if m[2] == "K"
    val *= 1024**2 if m[2] == "M"
    val *= 1024**3 if m[2] == "G"
    total += val
  end
  total.to_i
end

def parse_ab(out)
  rps    = out[/Requests per second:\s+([\d.]+)/, 1]&.to_f
  failed = out[/Failed requests:\s+(\d+)/, 1]&.to_i
  non2xx = out[/Non-2xx responses:\s+(\d+)/, 1]&.to_i
  p50    = out[/^\s*50%\s+([\d.]+)/, 1]&.to_f
  p95    = out[/^\s*95%\s+([\d.]+)/, 1]&.to_f
  p99    = out[/^\s*99%\s+([\d.]+)/, 1]&.to_f
  { rps: rps, failed: failed, non_2xx: non2xx, p50: p50, p95: p95, p99: p99 }
end

def median(xs)
  return nil if xs.empty? || xs.all?(&:nil?)
  s = xs.compact.sort
  return nil if s.empty?
  (s[(s.length - 1) / 2] + s[s.length / 2]) / 2.0
end

def aggregate_runs(runs)
  {
    rps: median(runs.map { |r| r[:rps] }),
    failed: runs.map { |r| r[:failed].to_i }.sum,
    p50: median(runs.map { |r| r[:p50] }),
    p95: median(runs.map { |r| r[:p95] }),
    p99: median(runs.map { |r| r[:p99] }),
    runs: runs.size,
  }
end

def measure_endpoint(port, path, **opts)
  runs = []
  RUNS.times { runs << run_ab(port, path, **opts) }
  aggregate_runs(runs)
end

def sample_memory(pids)
  { rss: rss_of(pids), unique: footprint_of(pids) }
end

def peak_memory(pids, prev)
  cur = sample_memory(pids)
  {
    rss: [prev[:rss].to_i, cur[:rss].to_i].max,
    unique: [prev[:unique].to_i, cur[:unique].to_i].max,
  }
end

def warmup_ab(port, path)
  # Best-effort warmup burst so every worker's caches are populated before we
  # measure (a single GET only warms one worker). Ignore output/errors.
  cmd = [AB, "-c", CONCURRENCY.to_s, "-t", WARMUP_DURATION.to_s, "-k", "-q", "-r",
         "http://127.0.0.1:#{port}#{path}"]
  system(cmd.shelljoin)
rescue StandardError
end

def benchmark_config
  {
    date: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
    ruby: RUBY_VERSION,
    rails: (Rails.version rescue "n/a"),
    ab: (`#{AB} -V 2>&1`[/\d+\.\d+\.\d+/] || "n/a"),
    concurrency: CONCURRENCY,
    duration: DURATION,
    warmup: WARMUP_DURATION,
    runs: RUNS,
    cores: NPROC,
    seed_email: USER_EMAIL,
  }
end

def write_results(results, cfg)
  FileUtils.mkdir_p(RESULTS_DIR)
  stamp = Time.now.strftime("%Y%m%d-%H%M%S")
  serial = results.map do |r|
    {
      scenario: r[:sc][:name],
      framing: r[:sc][:framing],
      mem_cold: r[:mem_cold],
      mem_peak: r[:mem_peak],
      up: r[:up], posts: r[:posts], post: r[:post],
      errors: r[:errors],
    }
  end
  payload = { config: cfg, results: serial }
  path = File.join(RESULTS_DIR, "bench-#{stamp}.json")
  File.write(path, JSON.pretty_generate(payload))
  puts "  results written to #{path}"
rescue StandardError => e
  puts "  (warn: could not write results file: #{e.message})"
end

def run_ab(port, path, method: :get, cookie: nil, postfile: nil, csrf: nil)
  cmd = [AB, "-c", CONCURRENCY.to_s, "-t", DURATION.to_s, "-k", "-q", "-r"]
  cmd += ["-C", cookie] if cookie
  cmd += ["-H", "X-CSRF-Token: #{csrf}"] if csrf
  if method == :post
    cmd += ["-T", "application/x-www-form-urlencoded", "-p", postfile]
  end
  cmd += ["http://127.0.0.1:#{port}#{path}"]
  out = `#{cmd.shelljoin} 2>&1`
  parse_ab(out)
end

def cookie_name_value(set_cookie_header)
  return nil unless set_cookie_header
  set_cookie_header.split(";").first.strip
end

# Pick the Rails session cookie out of a response's Set-Cookie headers.
# Falls back to the first Set-Cookie (which is the session cookie for this app).
def session_cookie(res)
  cks = res.get_fields("set-cookie") || [res["set-cookie"]].compact
  cks.map { |c| c.split(";").first.strip }
     .find { |c| c.downcase.include?("session") } || cks.map { |c| c.split(";").first.strip }.first
end

def get_form_token(port, path, cookie: nil)
  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Get.new(path)
  req["Cookie"] = cookie if cookie
  res = http.request(req)
  body = res.body.to_s
  # Prefer the <meta name="csrf-token"> tag. It is generated for the current
  # session (the token Turbo/remote forms send) and is unambiguous. A page
  # can carry MULTIPLE hidden-field authenticity_token inputs (e.g. a layout
  # `button_to` form), and the first one is not necessarily the main form's,
  # so relying on it yields a token that fails CSRF validation on the targeted
  # POST. Fall back to a hidden field only when no meta tag is present.
  token = body[/<meta name="csrf-token" content="([^"]*)"/i, 1] ||
          body[/name="authenticity_token"[^>]*value="([^"]*)"/, 1] ||
          body[/value="([^"]*)"[^>]*name="authenticity_token"/, 1]
  [token, cookie_name_value(res["set-cookie"])]
end

# Verify the write path works end-to-end: one authenticated POST /posts must
# persist and redirect (302) to the new post's show page. ab counts 302 as a
# "Non-2xx response", so we gate correctness here and measure throughput via ab
# separately (gated only on transport failures).
def verify_post_write(port, cookie, token)
  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Post.new("/posts")
  req["Cookie"] = cookie_name_value(cookie)
  req["X-CSRF-Token"] = token
  req.set_form_data("authenticity_token" => token, "post[title]" => "Verify", "post[body]" => "verify")
  res = http.request(req)
  unless res.code == "302" && res["location"] =~ %r{/posts/\d+\z}
    raise "POST /posts did not succeed: code=#{res.code} location=#{res['location'].inspect}"
  end
  res
end

# Full Devise sign-in dance -> returns [session cookie, create-form token]
def auth_cookie_and_create_token(port)
  tok1, sc1 = get_form_token(port, "/users/sign_in")
  raise "no sign-in CSRF token" unless tok1

  http = Net::HTTP.new("127.0.0.1", port)
  req = Net::HTTP::Post.new("/users/sign_in")
  req["Cookie"] = cookie_name_value(sc1)
  req.set_form_data(
    "user[email]" => USER_EMAIL,
    "user[password]" => USER_PW,
    "authenticity_token" => tok1,
  )
  res2 = http.request(req)
  auth_cookie = session_cookie(res2)
  raise "sign-in did not set a session cookie" unless auth_cookie

  tok3, sc3 = get_form_token(port, "/posts/new", cookie: auth_cookie)
  raise "no create-form CSRF token" unless tok3
  # Use the session cookie returned by the /posts/new GET. Rails may rotate the
  # session (and thus the CSRF token) after sign-in, so the token is valid for
  # the *latest* session cookie, not the one from the sign-in response.
  [sc3 || auth_cookie, tok3]
end

def ensure_user
  puts "  ensuring benchmark user #{USER_EMAIL} exists..."
  digest = `RAILS_ENV=test DATABASE_URL=#{DB_URL} bin/rails runner 'print Devise::Encryptor.digest(User, "password")'`.strip
  raise "could not compute password digest (got: #{digest.inspect})" if digest.empty?
  code = <<~RUBY
    email = ENV["BENCH_EMAIL"]
    digest = ENV["BENCH_DIGEST"]
    ActiveRecord::Base.connection.execute(
      "DELETE FROM users WHERE email = '\#{email}'")
    ActiveRecord::Base.connection.execute(
      "INSERT INTO users (email, encrypted_password, created_at, updated_at) " \\
      "VALUES ('\#{email}', '\#{digest}', now(), now())")
    puts "user ready"
  RUBY
  system({ "RAILS_ENV" => "test", "DATABASE_URL" => DB_URL,
           "BENCH_EMAIL" => USER_EMAIL, "BENCH_DIGEST" => digest },
         "bin/rails", "runner", code, exception: true)
end

# --- main ------------------------------------------------------------------
def main
  Dir.chdir(APP_DIR)
  ensure_user

  results = []

  SCENARIOS.each do |sc|
    puts "\n=== #{sc[:name]} [framing #{sc[:framing]}] ==="
    cleanup_port(PORT)
    pid = spawn(sc[:env], *sc[:cmd], err: "/tmp/#{sc[:pgrep]}_bench.log")
    r = { sc: sc, rss: nil, up: nil, posts: nil, post: nil, errors: {} }
    begin
      wait_ready(PORT, timeout: sc[:wait_timeout] || 90)
      # warmup: a real ab burst hits every worker so per-worker caches are
      # populated before we measure (a single GET only warms one worker).
      warmup_ab(PORT, "/up")
      warmup_ab(PORT, "/posts")

      pids = server_pids(PORT, pid)
      r[:mem_cold] = sample_memory(pids)
      r[:mem_peak] = r[:mem_cold].dup

      begin
        r[:up] = measure_endpoint(PORT, "/up")
        r[:mem_peak] = peak_memory(pids, r[:mem_peak])
        puts "  /up            rps=#{r[:up][:rps]&.round(1)} p50=#{r[:up][:p50]} p95=#{r[:up][:p95]} p99=#{r[:up][:p99]} failed=#{r[:up][:failed]} (n=#{r[:up][:runs]})"
      rescue StandardError => e
        r[:errors][:up] = "#{e.class}: #{e.message}"
        puts "  /up            FAILED: #{r[:errors][:up]}"
      end

      begin
        r[:posts] = measure_endpoint(PORT, "/posts")
        r[:mem_peak] = peak_memory(pids, r[:mem_peak])
        puts "  /posts (GET)   rps=#{r[:posts][:rps]&.round(1)} p50=#{r[:posts][:p50]} p95=#{r[:posts][:p95]} p99=#{r[:posts][:p99]} failed=#{r[:posts][:failed]} (n=#{r[:posts][:runs]})"
      rescue StandardError => e
        r[:errors][:posts] = "#{e.class}: #{e.message}"
        puts "  /posts (GET)   FAILED: #{r[:errors][:posts]}"
      end

      begin
        cookie, token = auth_cookie_and_create_token(PORT)
        verify_post_write(PORT, cookie, token)
        postdata = "authenticity_token=#{CGI.escape(token)}&post[title]=Benchmark&post[body]=Benchmark+body"
        Tempfile.create("postdata") do |f|
          f.write(postdata)
          f.flush
          r[:post] = measure_endpoint(PORT, "/posts", method: :post, cookie: cookie, postfile: f.path, csrf: token)
          if r[:post][:failed].to_i > 0
            r[:errors][:post] = "POST transport failures: #{r[:post][:failed]} (recorded, not aborted)"
            puts "  POST /posts    WARN: #{r[:errors][:post]}"
          end
          r[:mem_peak] = peak_memory(pids, r[:mem_peak])
          puts "  POST /posts    rps=#{r[:post][:rps]&.round(1)} p50=#{r[:post][:p50]} p95=#{r[:post][:p95]} p99=#{r[:post][:p99]} failed=#{r[:post][:failed]} (302=success; write path verified; n=#{r[:post][:runs]})"
        end
        # tidy the table so /posts GET stays fast for later scenarios
        system({ "DATABASE_URL" => DB_URL }, "psql", "-q", "-c", "DELETE FROM posts",
                "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test") rescue nil
      rescue StandardError => e
        r[:errors][:post] = "#{e.class}: #{e.message}"
        puts "  POST /posts    FAILED: #{r[:errors][:post]}"
      end
    rescue StandardError => e
      puts "  SCENARIO FAILED: #{e.class}: #{e.message}"
      r[:errors][:scenario] = "#{e.class}: #{e.message}"
    ensure
      # Release the port by killing the entire server tree. Don't rely on the
      # cmdline pattern alone: puma/kino rename their process title and fork
      # workers, so match whatever is actually LISTENing on the port (lsof)
      # plus the tracked pid's descendant tree.
      victims = ([pid].compact + descendant_pids(pid) + listening_pids(PORT)).uniq.reject { |v| !v || v.zero? }
      victims.each { |v| Process.kill("TERM", v) rescue nil }
      `pkill -f #{sc[:pgrep].shellescape}` rescue nil
      sleep 1
      victims.each { |v| Process.kill("KILL", v) rescue nil }
      cleanup_port(PORT)
      begin
        wait_port_free(PORT, timeout: 20)
      rescue StandardError => e
        puts "  (warn: #{e.message})"
      end
    end
    results << r
  end

  print_report(results)
end

def print_report(results)
  cfg = benchmark_config
  puts "\n\n# Benchmark results\n"
  puts "Date: #{cfg[:date]} | Ruby: #{cfg[:ruby]} | Rails: #{cfg[:rails]} | ab: #{cfg[:ab]}"
  puts "Concurrency: #{CONCURRENCY} | Duration: #{DURATION}s | Warmup: #{WARMUP_DURATION}s | Runs/endpoint: #{RUNS} | Keepalive: on | Cores: #{NPROC}"
  puts "Endpoints: /up (no DB), /posts (GET, DB+render), POST /posts (DB write+302)\n"

  [:up, :posts, :post].each do |ep|
    label = { up: "/up (GET, no DB)", posts: "/posts (GET, DB)", post: "POST /posts (write)" }[ep]
    puts "## #{label}\n"
    puts "| Server | Framing | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Failed (transport) |"
    puts "|--------|---------|------|----------|----------|----------|---------------------|"
    results.each do |r|
      m = r[ep]
      if m.nil?
        err = r[:errors][ep] || r[:errors][:scenario] || "unknown"
        puts "| #{r[:sc][:name]} | #{r[:sc][:framing]} | FAILED: #{err} |"
      else
        puts "| #{r[:sc][:name]} | #{r[:sc][:framing]} | #{m[:rps]&.round(1)} | #{m[:p50]} | #{m[:p95]} | #{m[:p99]} | #{m[:failed]} |"
      end
    end
    puts
  end

  puts "## Memory (process tree; cold = after warmup, peak = max during load)\n"
  puts "| Server | Framing | Cold RSS (MB) | Peak RSS (MB) | Cold Unique (MB) | Peak Unique (MB) |"
  puts "|--------|---------|---------------|--------------|-----------------|------------------|"
  results.each do |r|
    cold = r[:mem_cold]; peak = r[:mem_peak]
    if cold.nil?
      puts "| #{r[:sc][:name]} | #{r[:sc][:framing]} | FAILED | FAILED | FAILED | FAILED |"
    else
      cr = (cold[:rss].to_f / 1024).round(1)
      pr = (peak[:rss].to_f / 1024).round(1)
      cu = cold[:unique] && cold[:unique] > 0 ? (cold[:unique].to_f / 1024 / 1024).round(1) : "n/a"
      pu = peak[:unique] && peak[:unique] > 0 ? (peak[:unique].to_f / 1024 / 1024).round(1) : "n/a"
      puts "| #{r[:sc][:name]} | #{r[:sc][:framing]} | #{cr} | #{pr} | #{cu} | #{pu} |"
    end
  end
  puts "  RSS sum double-counts copy-on-write shared pages across forked workers;"
  puts "  Unique (macOS `footprint`, COW-aware) is the number to compare."
  puts

  write_results(results, cfg)
end

main if __FILE__ == $PROGRAM_NAME
