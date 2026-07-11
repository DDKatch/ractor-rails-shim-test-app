# frozen_string_literal: true

# Lightweight introspection endpoint for the memory benchmark harness.
# Served by kino worker Ractors. RSS is sampled by the harness (ps) using the
# returned pid; the shareable_* fields come from BENCH_SHAREABLE, a frozen hash
# computed once in the MAIN Ractor at boot (ObjectSpace.each_object only sees a
# worker's local heap, so the graph-wide shareable fraction must be captured
# before freezing, in the main Ractor).
class StatsController < ApplicationController
  def show
    gc = GC.stat
    shared = Object.const_get(:BENCH_SHAREABLE) rescue nil
    payload = {
      pid: Process.pid,
      gc_count: gc[:count],
      gc_major_count: gc[:major_gc_count],
      gc_minor_count: gc[:minor_gc_count],
      gc_time_ms: (GC::Profiler.total_time * 1000).round(2),
      total_allocated_objects: gc[:total_allocated_objects],
      heap_live_slots: gc[:heap_live_slots],
      heap_free_slots: gc[:heap_free_slots],
      shareable_bytes: shared && shared[:bytes],
      shareable_fraction: shared && shared[:fraction],
      shareable_total_bytes: shared && shared[:total_bytes],
      shareable_total_count: shared && shared[:total_count],
      shareable_count: shared && shared[:shareable_count]
    }
    # Use stdlib JSON.generate (not ActionController's `render json:`, which
    # reaches a Proc in the frozen shared graph and blows up under :ractor).
    render plain: JSON.generate(payload), content_type: "application/json"
  rescue => e
    render plain: JSON.generate(error: "#{e.class}: #{e.message}"),
           content_type: "application/json", status: 500
  end
end
