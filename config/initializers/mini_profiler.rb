# frozen_string_literal: true

# Rack MiniProfiler for Oopsie. Profiles every request, shows the speed
# badge and saved samples to logged-in users only.
# Template: brokerage commit aef3d116.
# Docs: https://github.com/MiniProfiler/rack-mini-profiler
if defined?(Rack::MiniProfiler)
  require "fileutils"
  if Rails.env.production?
    Rack::MiniProfiler.config.authorization_mode = :allow_authorized
    Rack::MiniProfiler.config.snapshot_every_n_requests = 5
    prod_path = File.expand_path("~/oopsie/shared/miniprofiler")
    FileUtils.mkdir_p(prod_path)
    Rack::MiniProfiler.config.storage_options = { path: prod_path }
  end
  if Rails.env.development?
    FileUtils.mkdir_p("/tmp/oopsie-miniprofiler")
    Rack::MiniProfiler.config.storage_options = { path: "/tmp/oopsie-miniprofiler" }
  end
  Rack::MiniProfiler.config.storage = Rack::MiniProfiler::FileStore
  Rack::MiniProfiler.config.skip_schema_queries = Rails.env.development?
  Rack::MiniProfiler.config.skip_paths += [ "/up", "/cable" ]
  Rack::MiniProfiler.config.position = "bottom-right"
  Rack::MiniProfiler.config.collapse_results = true
  Rack::MiniProfiler.config.max_traces_to_show = 20
  Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
  Rack::MiniProfiler.config.flamegraph_sample_rate = 0.5
  Rack::MiniProfiler.config.snapshots_redact_sql_queries = true
end
