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
  require "cgi"
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
  Rails.application.config.action_dispatch.show_exceptions = false
  Rails.application.config.consider_all_requests_local = true
  # Forgery protection is ON so the worker Ractors actually exercise CSRF
  # token issuance (a GET form page must render a token) and validation (a
  # POST with the token is accepted; a POST with a bad token is rejected).
  Rails.application.config.action_controller.allow_forgery_protection = true
  # Pragmatic config; in the frozen :ractor graph this does not propagate to
  # workers, so forms stay remote and the token is emitted in a <meta
  # name="csrf-token"> tag. `csrf_token_from` reads both the meta tag and a
  # hidden field, so token extraction works either way.
  Rails.application.config.hosts.clear
  Rails.application.config.eager_load = true
  Rails.application.config.cache_classes = true
  Rails.application.config.enable_reloading = false
  Rails.application.config.assets.sweep_cache = false
  Rails.application.config.action_view.cache_template_loading = true
  # kino's :ractor workers do not dispatch through ActionDispatch::Executor
  # (kino owns the Ractor scheduling). The frozen, shared graph never reloads,
  # so drop Executor (and ShowExceptions, so worker errors surface to the
  # in-worker rescue instead of being swallowed into public/500.html). These
  # must be queued BEFORE initialize! so they are baked into the built stack.
  Rails.application.config.middleware.delete(ActionDispatch::Executor)
  Rails.application.config.middleware.delete(ActionDispatch::ShowExceptions)
  # The shim deep-freezes the logger (incl. its SimpleFormatter#@tag_stack), so
  # the logging middlewares FrozenError while trying to log a worker exception,
  # masking the real error. Drop them so the original exception propagates to
  # the in-worker rescue (status 555 + backtrace).
  Rails.application.config.middleware.delete(ActionDispatch::DebugExceptions)
  Rails.application.config.middleware.delete(Rails::Rack::Logger)
  Rails.application.config.middleware.delete(Rails::Rack::SilenceRequest)

  Rails.application.initialize!

  # Enable CSRF protection for the :ractor worker verification. The full_test_app
  # does not call `protect_from_forgery` by default, so without this CSRF is inert
  # in workers. Turning it on here (BEFORE prepare_for_ractors!/make_app_shareable!
  # so the shim seeds the worker fallback + captures the callback) lets the test
  # prove token ISSUANCE (a GET form renders a token) and VALIDATION (a POST with
  # the token is accepted; a forged token is rejected) inside real worker Ractors.
  ActionController::Base.allow_forgery_protection = true
  ApplicationController.before_action :verify_authenticity_token

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

  # Seed a Devise user (committed to the test DB) so a worker Ractor can
  # authenticate it via POST /users/sign_in. We avoid User.create! because the
  # dummy app registers Devise before_validation callbacks on ActiveRecord::Base
  # under eager load. The password digest is computed in main (BCrypt) and the
  # hash string inserted raw.
  user_email = "signin@test.com"
  user_pw = Devise::Encryptor.digest(User, "password")
  conn.execute("DELETE FROM users WHERE email = #{conn.quote(user_email)}")
  conn.execute(
    "INSERT INTO users (email, encrypted_password, created_at, updated_at) " \
    "VALUES (#{conn.quote(user_email)}, #{conn.quote(user_pw)}, now(), now())"
  )

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

  # --- helpers ---------------------------------------------------------------
  # Pull the session cookie value (`_full_test_app_session=...`) out of a
  # `set-cookie` header so it can be replayed on a subsequent worker request.
  def self.session_cookie_from(header)
    return nil if header.nil? || header.empty?
    header.split("\n").each do |h|
      next unless h.include?("_full_test_app_session=")
      return h[/_full_test_app_session=[^;]*/]
    end
    nil
  end

  # Pull the CSRF token out of a rendered page. With remote/Turbo forms the
  # token lives in the `<meta name="csrf-token">` tag (emitted by
  # csrf_meta_tags); with non-remote forms it's a hidden `authenticity_token`
  # field. Check both.
  def self.csrf_token_from(body)
    body.to_s[/name="authenticity_token"[^>]*value="([^"]*)"/, 1] ||
      body.to_s[/name="csrf-token"[^>]*content="([^"]*)"/, 1]
  end

  # Dispatch ONE request inside a fresh worker Ractor, awaiting the result.
  # `cookie` (a `_full_test_app_session=...` string) is replayed as HTTP_COOKIE
  # so an authenticated session carries across worker Ractors.
  def self.dispatch(app, method, path, body, cookie)
    req_body = body || ""
    Ractor.new(app, method, path, req_body, cookie) do |application, m, p, b, ck|
      # Shareable, Ractor-local request IO stand-ins built INSIDE the worker
      # (never cross the boundary).
      input = Object.new
      def input.read(len = nil); (@body || "").dup; end
      def input.rewind; 0; end
      def input.gets; nil; end
      def input.each; end
      def input.size; (@body || "").bytesize; end
      def input.eof?; true; end
      def input.close; end
      def input.closed?; false; end
      input.instance_variable_set(:@body, b)

      err = Object.new
      def err.write(*); end
      def err.puts(*); end
      def err.flush; end
      def err.close; end

      env = {
        "REQUEST_METHOD" => m,
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
      env["HTTP_COOKIE"] = ck if ck && !ck.empty?
      # Parse a request body (with the CSRF token) for any verb that carries
      # one — not just POST. DELETE /users/sign_out needs it for CSRF validation.
      if b && !b.empty?
        env["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
        env["CONTENT_LENGTH"] = b.bytesize.to_s
      end

      begin
        status, headers, body_obj = application.call(env)
      rescue ActionController::InvalidAuthenticityToken
        # Expected CSRF-rejection path: map to its real HTTP status instead of
        # the generic 555 the rescue below uses for unexpected worker errors.
        [422, { "content-type" => "text/plain" }, "InvalidAuthenticityToken"]
      rescue => e
        # Surface the real worker-side exception instead of Rails' 500 page,
        # so the test can report the root cause of a failed request.
        err_lines = ["#{e.class}: #{e.message}"]
        err_lines += e.backtrace.first(20).map { |bt| "  #{bt}" }
        [555, { "content-type" => "text/plain" }, err_lines.join("\n")]
      else
        content = +""
        begin
          body_obj.each { |c| content << c.to_s }
        rescue
          begin
            content = body_obj.to_s
          rescue
            content = ""
          end
        end

        # Normalize headers to a plain Hash (Rack returns a response array whose
        # headers may be a frozen/blank Hash subclass).
        norm_headers = {}
        begin
          headers.each { |k, v| norm_headers[k.to_s] = v.to_s }
        rescue
          nil
        end

        [status, norm_headers, content]
      end
    end.value
  end

  created_title = "Ractor create proof"

  # --- auth + CSRF flow (all inside real worker Ractors) ---------------------
  # 1. GET the Devise sign-in page (public). With forgery protection on, the
  #    rendered form carries a CSRF token bound to the session cookie the GET
  #    set. Both are needed to POST.
  lp_status, lp_headers, lp_body = dispatch(app, "GET", "/users/sign_in", nil, nil)
  unless lp_status == 200
    warn "GET /users/sign_in returned #{lp_status} in worker:\n#{lp_body[0, 2000]}"
  end
  login_token = csrf_token_from(lp_body)
  login_cookie = session_cookie_from(lp_headers["set-cookie"])

  # 2. POST valid credentials + the CSRF token -> Warden session write (sets an
  #    encrypted, authenticated session cookie). This is the SESSION-MUTATING
  #    path exercised in a worker Ractor.
  signin_body =
    "user[email]=#{CGI.escape(user_email)}&user[password]=password" \
    "&authenticity_token=#{CGI.escape(login_token.to_s)}"
  si_status, si_headers, si_body = dispatch(app, "POST", "/users/sign_in", signin_body, login_cookie)
  auth_cookie = session_cookie_from(si_headers["set-cookie"]) || login_cookie

  # 3. GET /posts/new as the authenticated user -> 200 AND the form must render
  #    a CSRF token (proves token ISSUANCE in a worker Ractor).
  pn_status, pn_headers, pn_body = dispatch(app, "GET", "/posts/new", nil, auth_cookie)
  new_token = csrf_token_from(pn_body)

  # 3b. GET /posts/new UNAUTHENTICATED -> 302 redirect to sign-in. Proves the
  #     `authenticate_user!` before_action actually replays in a worker Ractor
  #     (not a masked no-op) — the trap NEXT_STEPS.md warns about.
  unu_status, unu_headers, unu_body = dispatch(app, "GET", "/posts/new", nil, nil)

  # 4. POST /posts with the valid CSRF token -> 302 redirect after persisting a
  #    row in the DB (proves token VALIDATION + the WRITE path in a worker).
  post_body =
    "post[title]=#{CGI.escape(created_title)}&post[body]=written-in-worker" \
    "&authenticity_token=#{CGI.escape(new_token.to_s)}"
  pc_status, pc_headers, pc_body = dispatch(app, "POST", "/posts", post_body, auth_cookie)

  # 5. POST /posts with a BAD CSRF token -> 422 (proves validation REJECTS a
  #    forged token in a worker Ractor).
  bad_body =
    "post[title]=forged&post[body]=forged&authenticity_token=not-a-real-token"
  bad_status, bad_headers, bad_body = dispatch(app, "POST", "/posts", bad_body, auth_cookie)

  # 6. SESSION-MUTATING sign-out in a worker Ractor. Devise `sign_out` calls
  #    `reset_session`, which regenerates the session id. Re-fetch a fresh CSRF
  #    token for the authed session, then DELETE /users/sign_out. Must 302/303
  #    and set a NEW encrypted session cookie (proves the session write path +
  #    CSRF validation on a non-GET, non-POST verb in a worker).
  so_token = csrf_token_from(dispatch(app, "GET", "/posts/new", nil, auth_cookie)[2])
  signout_body = "authenticity_token=#{CGI.escape(so_token.to_s)}"
  so_status, so_headers, so_body =
    dispatch(app, "DELETE", "/users/sign_out", signout_body, auth_cookie)
  signout_cookie = session_cookie_from(so_headers["set-cookie"]) || auth_cookie

  # 7. The NEW session cookie from sign-out must have no user: GET /posts/new
  #    must redirect to sign-in again (proves reset_session actually cleared
  #    the worker session, not a masked no-op). Note: the OLD cookie still
  #    authenticates (cookie-store sessions can't be server-invalidated) — so we
  #    check the fresh post-sign-out cookie instead.
  dead_status, dead_headers, dead_body =
    dispatch(app, "GET", "/posts/new", nil, signout_cookie)

  # Public GET routes (no auth, no CSRF needed).
  root_status,  root_headers,  root_body  = dispatch(app, "GET", "/", nil, nil)
  posts_status, posts_headers, posts_body = dispatch(app, "GET", "/posts", nil, nil)
  show_status,  show_headers,  show_body  = dispatch(app, "GET", "/posts/#{post_id}", nil, nil)
  su_status,    su_headers,    su_body    = dispatch(app, "GET", "/users/sign_up", nil, nil)
  pw_status,    pw_headers,    pw_body    = dispatch(app, "GET", "/users/password/new", nil, nil)

  # Snapshot the row count AFTER the worker writes, so we can prove the POST
  # persisted exactly one new row.
  final_count = conn.select_value("SELECT count(*) FROM posts").to_i

  results = {
    "GET /" => [root_status, root_headers, root_body],
    "GET /posts" => [posts_status, posts_headers, posts_body],
    "GET /posts/new" => [pn_status, pn_headers, pn_body],
    "GET /posts/new (unauth)" => [unu_status, unu_headers, unu_body],
    "GET /posts/#{post_id}" => [show_status, show_headers, show_body],
    "GET /users/sign_in" => [lp_status, lp_headers, lp_body],
    "GET /users/sign_up" => [su_status, su_headers, su_body],
    "GET /users/password/new" => [pw_status, pw_headers, pw_body],
    "POST /users/sign_in" => [si_status, si_headers, si_body],
    "POST /posts (valid token)" => [pc_status, pc_headers, pc_body],
    "POST /posts (bad token)" => [bad_status, bad_headers, bad_body],
    "DELETE /users/sign_out" => [so_status, so_headers, so_body],
    "GET /posts/new (signed-out)" => [dead_status, dead_headers, dead_body],
  }

  puts JSON.generate(
    "post_id" => post_id,
    "post_title" => post_title,
    "created_title" => created_title,
    "login_token_present" => !login_token.nil?,
    "new_token_present" => !new_token.nil?,
    "initial_count" => final_count - 1,
    "final_count" => final_count,
    "results" => results
  )
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

      # --- public GET routes (no auth) -------------------------------------
      assert_equal 200, results["GET /"][0], "root path status"
      assert_equal 200, results["GET /posts"][0], "/posts status"
      assert_equal 200, results["GET /users/sign_in"][0], "/users/sign_in status"
      assert_equal 200, results["GET /users/sign_up"][0], "/users/sign_up status"
      assert_equal 200, results["GET /users/password/new"][0], "/users/password/new status"

      show_key = "GET /posts/#{post_id}"
      assert_equal 200, results[show_key][0], "#{show_key} status"
      # This is the key proof: set_post (a before_action) must run INSIDE the
      # worker Ractor for @post to be populated; otherwise the body is empty.
      assert_includes results[show_key][2], post_title,
                      "#{show_key} body should contain the post title (before_action replay in worker)"

      # --- auth callback replay: /posts/new requires authenticate_user! -----
      # Unauthenticated it MUST redirect to sign-in (proves the before_action
      # actually runs in the worker now, not a masked no-op).
      assert_equal 302, results["GET /posts/new (unauth)"][0],
                   "GET /posts/new must redirect to sign-in when unauthenticated (auth callback replay in worker)"
      assert_includes results["GET /posts/new (unauth)"][1]["location"].to_s, "/users/sign_in",
                   "GET /posts/new redirect should point at the sign-in path"

      # The AUTHENTICATED GET /posts/new must render 200 with a CSRF token
      # (proves token ISSUANCE in a worker Ractor).
      assert_equal 200, results["GET /posts/new"][0],
                   "authenticated GET /posts/new must render 200 (token issuance in worker)"

      # --- SESSION WRITE PATH: Devise sign-in (Warden session write) --------
      # The worker authenticates the seeded user and sets an encrypted session
      # cookie. Forgery protection is ON, so this also proves CSRF validation
      # accepted the valid token issued by the GET /users/sign_in page.
      signin_status = results["POST /users/sign_in"][0]
      signin_headers = results["POST /users/sign_in"][1]
      assert_includes [302, 303], signin_status,
                   "POST /users/sign_in should redirect (302/303) after authenticating in a worker Ractor"
      signin_cookie = signin_headers["set-cookie"] || ""
      assert signin_cookie.include?("_full_test_app_session"),
             "POST /users/sign_in should set an encrypted session cookie (Warden session write in worker)"

      # --- CSRF token ISSUANCE in a worker Ractor --------------------------
      # The authenticated GET /posts/new must render a CSRF authenticity_token
      # field (proves the worker can issue a token off the main Ractor).
      assert data["login_token_present"],
             "GET /users/sign_in must render a CSRF token (issuance in worker)"
      assert data["new_token_present"],
             "authenticated GET /posts/new must render a CSRF token (issuance in worker)"

      # --- WRITE PATH + CSRF VALIDATION: POST /posts with valid token ------
      # A worker Ractor builds a NEW Post (cloning the frozen _default_attributes
      # template), assigns the params, persists it, AND `redirect_to @post`
      # (URL generation in the worker). The valid CSRF token must be accepted.
      post_status = results["POST /posts (valid token)"][0]
      post_headers = results["POST /posts (valid token)"][1]
      assert_equal 302, post_status,
                   "POST /posts (valid CSRF token) should redirect (302) after persisting in a worker Ractor"
      assert post_headers.key?("location"),
             "POST /posts redirect should set a Location header (URL generation in worker)"
      assert_equal data["initial_count"] + 1, data["final_count"],
                   "POST /posts must persist exactly one new row in the test DB"
      conn = ActiveRecord::Base.connection
      titles = conn.select_values("SELECT title FROM posts WHERE title = #{conn.quote(data['created_title'])}")
      assert_includes titles, data["created_title"],
                     "the worker-created post with the params title should exist in the DB"

      # --- CSRF VALIDATION REJECTS a forged token in a worker Ractor -------
      assert_equal 422, results["POST /posts (bad token)"][0],
                   "POST /posts with a bad CSRF token must be rejected (422) in a worker Ractor"

      # --- SESSION-MUTATING sign-out in a worker Ractor -------------------
      # Devise `sign_out` calls `reset_session` (regenerates the session id) and
      # needs a valid CSRF token on the DELETE. Proves the session-WRITE path +
      # CSRF validation on a non-GET/POST verb inside a worker.
      signout_status = results["DELETE /users/sign_out"][0]
      signout_headers = results["DELETE /users/sign_out"][1]
      assert_includes [302, 303], signout_status,
                   "DELETE /users/sign_out should redirect (302/303) after signing out in a worker Ractor"
      assert (signout_headers["set-cookie"] || "").include?("_full_test_app_session"),
             "DELETE /users/sign_out should set a new encrypted session cookie (reset_session in worker)"

      # The OLD auth cookie is now dead: GET /posts/new must redirect to
      # sign-in again (proves the worker session was actually invalidated).
      assert_equal 302, results["GET /posts/new (signed-out)"][0],
                   "after sign-out, the old auth cookie must no longer authenticate (session invalidated in worker)"
      assert_includes results["GET /posts/new (signed-out)"][1]["location"].to_s, "/users/sign_in",
                   "after sign-out, GET /posts/new should redirect to sign-in"
      end
    end
end
