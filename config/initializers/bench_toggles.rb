# frozen_string_literal: true

# Benchmark-only toggles (see bench/bench.rb). Each toggle removes ONE
# per-request cost so its contribution can be measured in isolation. Unset in
# normal operation, so this file is a no-op outside a profiling run.
#
#   BENCH_NO_TURBO_TRACKING=1  -> skip turbo-rails' around_action that sets
#                                 Turbo.current_request_id on every request
#                                 (the shim replays around filters wrap-style)

if ENV["BENCH_NO_TURBO_TRACKING"] == "1"
  ActiveSupport.on_load(:action_controller_base) do
    if respond_to?(:skip_around_action) &&
       _process_action_callbacks.any? { |cb| cb.filter == :turbo_tracking_request_id }
      skip_around_action :turbo_tracking_request_id
      Rails.logger.warn("[bench] turbo_tracking_request_id around_action skipped") if defined?(Rails.logger) && Rails.logger
    end
  end
end
