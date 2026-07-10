#!/usr/bin/env ruby
# frozen_string_literal: true

# Load test that reproduces "refresh the page too quickly" errors against a
# RUNNING server (e.g. kino -m ractor). The in-process Minitest
# (test/integration/root_load_test.rb) cannot reproduce ractor-worker
# connection handling, so use this against the real server.
#
# Usage:
#   ruby load_root.rb [url] [duration_sec] [concurrency] [rate_per_sec]
#
# Defaults: hits http://127.0.0.1:9293/ for 10s, 12 in-flight, ~10 req/s.
# Concurrency > database.yml `pool: 5` is what surfaces pool exhaustion.
require "net/http"
require "uri"

url         = ARGV[0] || "http://127.0.0.1:9293/"
duration    = (ARGV[1] || 10).to_i
concurrency = (ARGV[2] || 12).to_i
rate        = (ARGV[3] || 10).to_i

uri = URI(url)
per_thread_sleep = concurrency.to_f / rate

completed = 0
failed    = 0
errors    = Hash.new(0)
start     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
stop      = false

threads = concurrency.times.map do
  Thread.new do
    http = Net::HTTP.start(uri.host, uri.port, read_timeout: 30)
    until stop
      begin
        res = http.get(uri.request_uri)
        if res.code == "200"
          completed += 1
        else
          failed += 1
          errors["HTTP #{res.code}"] += 1
        end
      rescue => ex
        failed += 1
        errors["#{ex.class}: #{ex.message[0, 100]}"] += 1
        begin
          http.finish
        rescue StandardError
          nil
        end
        begin
          http = Net::HTTP.start(uri.host, uri.port, read_timeout: 30)
        rescue StandardError
          nil
        end
      end
      sleep per_thread_sleep
    end
    begin
      http.finish
    rescue StandardError
      nil
    end
  end
end

sleep duration
stop = true
threads.each(&:join)

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
total   = completed + failed
puts "Target:      #{url}"
puts "Duration:    #{elapsed.round(2)}s"
puts "Concurrency: #{concurrency}  (database.yml pool: 5)"
puts "Rate target: #{rate}/s"
puts "Completed:   #{completed}"
puts "Failed:      #{failed}"
puts "Req/s:       #{(total / elapsed).round(2)}"
puts "Errors:"
errors.each { |k, v| puts "  #{v}x #{k}" }
