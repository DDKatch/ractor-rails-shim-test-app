# frozen_string_literal: true

# Integration test that exercises the Frozen, shared Ractor graph (kino
# :ractor mode) through REAL worker Ractors — not the main Ractor.
#
# The test file is dual-purpose:
#
#   * Run normally (bin/rails test), it spawns a SUBPROCESS (RACTOR_BOOT_SUBPROCESS=1)
#     that boots the app in frozen :ractor mode, dispatches a set of GET requests
#     into a pool of worker Ractors, and prints a JSON report of status + body per
#     route. The parent process parses the report and asserts.
#
#   * The subprocess branch boots the app exactly the way config_ractor.ru's
#     :ractor path does (install shim -> eager load -> prepare_for_ractors! ->
#     make_app_shareable! -> WorkerApp wrap), then runs the requests inside
#     Ractors so the frozen graph is the ONLY app state available (proving the
#     shim's callback replay, constant rebinding, and ActiveRecord worker
#     connection init all work off the main Ractor).
#
# Running the ractor boot in a subprocess keeps it isolated from the parent
# test process, which is already booted in normal (lazy, non-frozen) test mode.

if ENV["RACTOR_BOOT_SUBPROCESS"] == "1"
  require "bundler/setup"
  require "json"
  require "ractor_rails_shim"

  RactorRailsShim.install

  # Boot with PRODUCTION semantics (eager_load + cache_classes + reloading off)
  # — the exact, verified kino :ractor path from config_ractor.ru. Forcing the
  # test environment's lazy/autoload settings here corrupted class loading
  # (models picked up Devise methods), so we mirror production instead and just
  # point the database at the already-migrated test database.
  ENV["RAILS_ENV"] ||= "production"
  ENV["DATABASE_URL"] ||= "postgresql://dev@127.0.0.1:5432/full_test_app_test"

  require_relative File.expand_path("../../config/application", __dir__)

  # Test-harness overrides on top of the production config.
  Rails.application.config.secret_key_base = "0" * 128
  Rails.application.config.action_dispatch.show_exceptions = :all
  Rails.application.config.consider_all_requests_local = true
  Rails.application.config.hosts.clear
  Rails.application.config.eager_load = true
  Rails.application.config.cache_classes = true
  Rails.application.config.enable_reloading = false
  Rails.application.config.assets.sweep_cache = false
  Rails.application.config.action_view.cache_template_loading = true

  Rails.application.initialize!

  # kino's :ractor workers do not dispatch through ActionDispatch::Executor
  # (kino owns the Ractor scheduling), so drop it here: otherwise each worker
  # request runs Rails.application.reloader.to_run -> require_unload_lock!,
  # which is not Ractor-safe. The frozen, shared graph never reloads anyway.
  Rails.application.middleware.delete(ActionDispatch::Executor) rescue nil

  # Confirm the frozen graph actually holds the app routes (not just the railtie).
  anchored = Rails.application.routes.routes.anchored_routes.size
  unless anchored > 1
    warn "ractor boot: only #{anchored} anchored routes drawn"
    puts JSON.generate("error" => "only #{anchored} anchored routes drawn")
    exit 1
  end

  # Seed a deterministic Post via raw SQL (committed to the test DB) so worker
  # Ractors (separate AR connections) can read it via set_post. Done in the main
  # Ractor before the graph is frozen. We avoid Post.create!/insert! because the
  # dummy app registers Devise's downcase_keys/strip_whitespace before_validation
  # callbacks on ActiveRecord::Base under eager load, which would otherwise raise
  # on a plain Post. GET requests served by workers never trigger those callbacks.
  conn = ActiveRecord::Base.connection
  conn.execute(
    "INSERT INTO posts (title, body, created_at, updated_at) " \
    "VALUES ('Ractor proof', 'set_post ran in worker', now(), now())"
  )
  post_id = conn.select_value("SELECT currval('posts_id_seq')").to_i
  post_title = "Ractor proof"

  unless RactorRailsShim.respond_to?(:prepare_for_ractors!)
    warn "ractor-rails-shim not available"
    puts JSON.generate("error" => "ractor-rails-shim not available")
    exit 1
  end

  RactorRailsShim.prepare_for_ractors!
  app_constants = RactorRailsShim.capture_app_constants
  app = RactorRailsShim.make_app_shareable!(Rails.application)
  app = Ractor.make_shareable(RactorRailsShim::WorkerApp.new(app, app_constants))

  # Mirror config_ractor.ru: shareable ParamBuilder default.
  if defined?(::ActionDispatch::ParamBuilder)
    pb = ::ActionDispatch::ParamBuilder
    fd = pb.make_default(100)
    fd.freeze
    Ractor.make_shareable(fd) rescue nil
    pb.const_set(:RACTOR_SHAREABLE_DEFAULT, fd) rescue nil
    pb.singleton_class.class_eval <<-RUBY
      def default
        ::ActionDispatch::ParamBuilder::RACTOR_SHAREABLE_DEFAULT
      end
    RUBY
  end

  paths = [
    "/",
    "/posts",
    "/posts/new",
    "/posts/#{post_id}",
    "/users/sign_in",
    "/users/sign_up",
    "/users/password/new",
  ]

  # Spawn one worker Ractor per request. In Ruby 4.0 a Ractor returns its block
  # value (read via #value); the frozen, shared `app` is passed in (it is
  # shareable, so it crosses the boundary). Each worker builds its own Rack env
  # from the path and returns [path, status, body].
  results = {}
  ractors = paths.map do |path|
    Ractor.new(app, path) do |application, p|
      # Shareable, Ractor-local request IO stand-ins built INSIDE the worker
      # (never cross the boundary).
      input = Object.new
      def input.read; ""; end
      def input.rewind; 0; end
      def input.gets; nil; end
      def input.each; end
      def input.size; 0; end
      def input.eof?; true; end
      def input.close; end
      def input.closed?; false; end

      err = Object.new
      def err.write(*); end
      def err.puts(*); end
      def err.flush; end
      def err.close; end

      env = {
        "REQUEST_METHOD" => "GET",
        "SCRIPT_NAME" => "",
        "PATH_INFO" => p,
        "QUERY_STRING" => "",
        "SERVER_NAME" => "example.com",
        "SERVER_PORT" => "80",
        "HTTP_HOST" => "example.com",
        "rack.version" => [1, 3],
        "rack.url_scheme" => "http",
        "rack.input" => input,
        "rack.errors" => err,
        "rack.multithread" => false,
        "rack.multiprocess" => true,
        "rack.run_once" => false,
      }

      status, _headers, body = application.call(env)

      content = +""
      begin
        body.each { |c| content << c.to_s }
      rescue
        begin
          content = body.to_s
        rescue
          content = ""
        end
      end

      [p, status, content]
    end
  end

  ractors.each_with_index do |r, i|
    returned_path, status, content = r.value
    results[returned_path] = [status, content]
  end

  puts JSON.generate("post_id" => post_id, "post_title" => post_title, "results" => results)
  exit 0
else
  require "test_helper"
  require "json"
  require "open3"

  class RactorServerTest < ActionDispatch::IntegrationTest
    test "frozen :ractor app serves routes from worker Ractors" do
      env = {
        "RACTOR_BOOT_SUBPROCESS" => "1",
        "RAILS_ENV" => "production",
        "DATABASE_URL" => "postgresql://dev@127.0.0.1:5432/full_test_app_test",
      }
      cmd = ["bundle", "exec", "ruby", "-Itest", "-Ilib", __FILE__]
      stdout, stderr, status = Open3.capture3(env, *cmd, chdir: Rails.root.to_s)

      assert status.success?,
             "ractor boot subprocess failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"

      data = JSON.parse(stdout)
      refute data.key?("error"), "ractor boot reported error: #{data['error']}"

      results = data["results"]
      post_id = data["post_id"]
      post_title = data["post_title"]

      assert_equal 200, results["/"][0], "root path status"
      assert_equal 200, results["/posts"][0], "/posts status"
      assert_equal 200, results["/posts/new"][0], "/posts/new status"

      show_key = "/posts/#{post_id}"
      assert_equal 200, results[show_key][0], "#{show_key} status"
      # This is the key proof: set_post (a before_action) must run INSIDE the
      # worker Ractor for @post to be populated; otherwise the body is empty.
      assert_includes results[show_key][1], post_title,
                      "#{show_key} body should contain the post title (before_action replay in worker)"

      assert_equal 200, results["/users/sign_in"][0], "/users/sign_in status"
      assert_equal 200, results["/users/sign_up"][0], "/users/sign_up status"
      assert_equal 200, results["/users/password/new"][0], "/users/password/new status"
    end
  end
end
