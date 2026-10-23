#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare two bench/results/*.json runs scenario-by-scenario.
#
#   ruby bench/compare.rb                      # latest vs the one before it
#   ruby bench/compare.rb OLD.json NEW.json
#
# Prints requests/sec for each endpoint plus the delta percentage, and the
# peak memory (RSS in KB / unique bytes) of each server.
require "json"

def load_run(path)
  data = JSON.parse(File.read(path))
  [data["config"] || {}, data["results"] || []]
end

def latest_two
  files = Dir[File.expand_path("results/*.json", __dir__)].sort_by { |f| File.mtime(f) }
  raise "need at least two results files" if files.size < 2

  files.last(2)
end

def pct(new_value, old_value)
  return "n/a" if old_value.nil? || old_value.to_f.zero?

  format("%+.1f%%", (new_value.to_f - old_value.to_f) / old_value.to_f * 100.0)
end

old_path, new_path = ARGV.size >= 2 ? ARGV : latest_two
old_cfg, old_rows = load_run(old_path)
new_cfg, new_rows = load_run(new_path)

puts "OLD: #{File.basename(old_path)}  #{old_cfg['date']}  (dur=#{old_cfg['duration']}s runs=#{old_cfg['runs']})"
puts "NEW: #{File.basename(new_path)}  #{new_cfg['date']}  (dur=#{new_cfg['duration']}s runs=#{new_cfg['runs']})"
puts

old_by_name = old_rows.to_h { |r| [r["scenario"], r] }

header = format("%-34s %9s %9s %8s | %9s %9s %8s", "scenario", "up old", "up new", "delta",
                "posts old", "posts new", "delta")
puts header
puts "-" * header.length

new_rows.each do |row|
  old = old_by_name[row["scenario"]] || {}
  up_old = old.dig("up", "rps").to_f
  up_new = row.dig("up", "rps").to_f
  p_old = old.dig("posts", "rps").to_f
  p_new = row.dig("posts", "rps").to_f
  puts format("%-34s %9.1f %9.1f %8s | %9.1f %9.1f %8s",
              row["scenario"], up_old, up_new, pct(up_new, up_old),
              p_old, p_new, pct(p_new, p_old))
end

puts
puts "peak memory (RSS KB / unique MB):"
new_rows.each do |row|
  old = old_by_name[row["scenario"]] || {}
  old_mem = old["mem_peak"] || {}
  new_mem = row["mem_peak"] || {}
  puts format("%-34s %10s -> %10s | %6s -> %6s",
              row["scenario"],
              old_mem["rss"], new_mem["rss"],
              old_mem["unique"] && (old_mem["unique"] / 1024.0 / 1024.0).round(1),
              new_mem["unique"] && (new_mem["unique"] / 1024.0 / 1024.0).round(1))
end
