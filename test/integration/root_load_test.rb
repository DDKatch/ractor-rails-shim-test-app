# frozen_string_literal: true

require "test_helper"
require "net/http"
require "uri"
require "socket"

# Load test that boots the dummy app under the **kino :ractor web server**
# (just like production) and hammers the root page at a sustained rate with
# more concurrency than the PostgreSQL connection pool (database.yml
# `pool: 5`). This reproduces "refresh too quickly" errors that only show up
# through the real worker-Ractor path (session/connection handling), which the
# in-process `Rails.application.call` loop cannot exercise.
#
#   bin/rails test test/integration/root_load_test.rb
#
# The server is started in `setup` and killed in `teardown`, so the test is
# self-contained. If you already have a kino server running, set
# SKIP_KINO_BOOT=1 and point KINO_URL at it.
class RootLoadTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = [] if respond_to?(:fixture_table_names=)

  RATE_PER_SEC = 10      # target throughput
  CONCURRENCY  = 12      # in-flight requests (> database.yml pool: 5)
  DURATION_SEC = 8
  PORT = (ENV["KINO_PORT"] || 9293).to_i
  HOST = "127.0.0.1"
  URL  = ENV["KINO_URL"] || "http://#{HOST}:#{PORT}/"

  def setup
    super
    prepare_prod_db_once
    @server_pid = boot_kino unless ENV["SKIP_KINO_BOOT"]
    wait_for_server
    warm_up
  end

  def teardown
    if @server_pid
      Process.kill("TERM", @server_pid) rescue nil
      Process.wait(@server_pid) rescue nil
    end
    super
  end

  test "root page survives rapid concurrent load via kino :ractor" do
    failures = []
    totals   = Hash.new(0)
    stop     = false
    mutex    = Mutex.new
    per_thread_sleep = CONCURRENCY.to_f / RATE_PER_SEC

    threads = CONCURRENCY.times.map do
      Thread.new do
        until stop
          begin
            res = Net::HTTP.get_response(URI(URL))
            if res.code.to_i >= 500
              mutex.synchronize { failures << "HTTP #{res.code}" }
            end
          rescue => ex
            klass = ex.class.name
            mutex.synchronize do
              failures << "#{klass}: #{ex.message}"
              totals[klass] += 1
            end
          end
          sleep per_thread_sleep
        end
      end
    end

    sleep DURATION_SEC
    stop = true
    threads.each(&:join)

    if failures.empty?
      assert true
    else
      summary = totals.map { |k, v| "#{k} x#{v}" }.join(", ")
      assert failures.empty?,
             "Root page failed under kino :ractor load " \
             "(#{failures.size} failures: #{summary}).\n" \
             "Sample:\n#{failures.uniq.first(5).join("\n")}"
    end
  end

  private

  def prepare_prod_db_once
    return if ENV["SKIP_KINO_BOOT"]
    system(
      { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "dummy",
        "BUNDLE_GEMFILE" => File.join(Rails.root, "Gemfile") },
      "bundle", "exec", "rails", "db:prepare",
      chdir: Rails.root.to_s, out: File::NULL, err: File::NULL
    )
  end

  def boot_kino
    log = "/tmp/kino_load_test.log"
    pid = Process.spawn(
      { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "dummy",
        "BUNDLE_GEMFILE" => File.join(Rails.root, "Gemfile"),
        "PATH" => ENV["PATH"] },
      "bundle", "exec", "kino", "-C", "kino.rb", "config_ractor.ru",
      chdir: Rails.root.to_s, out: log, err: log
    )
    pid
  end

  def wait_for_server(timeout: 90)
    deadline = Time.now + timeout
    loop do
      begin
        Net::HTTP.get_response(URI(URL))
        return
      rescue SystemCallError, Net::ReadTimeout, Errno::ECONNREFUSED
        raise "kino :ractor server did not become ready within #{timeout}s " \
              "(see /tmp/kino_load_test.log)" if Time.now > deadline
        sleep 0.5
      end
    end
  end

  # A single request must succeed before we start the load, otherwise the
  # failures below would just be "DB not migrated / server unhealthy".
  def warm_up
    res = Net::HTTP.get_response(URI(URL))
    return if res.code.to_i == 200

    log = File.read("/tmp/kino_load_test.log") rescue "(no log)"
    flunk "kino server is not healthy before load: HTTP #{res.code}\n#{log[-1500..]}"
  end
end
