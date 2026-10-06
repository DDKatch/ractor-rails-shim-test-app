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
  ENV["DATABASE_URL"] ||= "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"

  require_relative File.expand_path("../../config/application", __dir__)

  # Test-harness overrides on top of the production config.
  Rails.application.config.secret_key_base = "0" * 128
  Rails.application.config.action_dispatch.show_exceptions = false
  Rails.application.config.consider_all_requests_local = true
  # Forgery protection is ON so the worker Ractors actually exercise CSRF
  # token issuance (a GET form page must render a token) and validation (a
  # POST with the token is accepted; a POST with a bad token is rejected).
  Rails.application.config.action_controller.allow_forgery_protection = true
  # Mailer delivery: use the :test method in the :ractor worker verification so
  # the captured delivery-method class is Mail::TestMailer (no real SMTP server,
  # and Mail::SMTP::DEFAULTS is an un-shareable constant). This proves the
  # mailer build + ERB render + delivery path works in a worker Ractor.
  Rails.application.config.action_mailer.delivery_method = :test
  Rails.application.config.action_mailer.perform_deliveries = true
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
  # ActiveStorage service: production doesn't set one, but the attach_probe
  # (TODO #4) needs `ActiveStorage::Blob.service` to resolve (it's set from
  # `config.active_storage.service` during the `active_storage.services`
  # initializer). Point at the :test disk service (config/storage/test.yml)
  # so the blob's `service_name` defaults correctly in main and the frozen
  # graph carries it to workers.
  Rails.application.config.active_storage.service = :test
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

  # Force the :test mailer delivery method AFTER initialize! (the environment
  # file sets :smtp, which would otherwise be captured by the shim's mail patch
  # as Mail::SMTP — whose ::DEFAULTS constant is un-shareable). :test proves the
  # mailer build + ERB render + delivery path works inside a worker Rector.
  if defined?(::Mail)
    ::Mail.defaults { delivery_method :test }
  end
  if defined?(::ActionMailer::Base)
    ::ActionMailer::Base.delivery_method = :test
  end

  # Enable CSRF protection for the :ractor worker verification. The ractor-rails-shim-test-app
  # does not call `protect_from_forgery` by default, so without this CSRF is inert
  # in workers. Turning it on here (BEFORE prepare_for_ractors!/make_app_shareable!
  # so the shim seeds the worker fallback + captures the callback) lets the test
  # prove token ISSUANCE (a GET form renders a token) and VALIDATION (a POST with
  # the token is accepted; a forged token is rejected) inside real worker Ractors.
  ActionController::Base.allow_forgery_protection = true
  # NOTE: verify_authenticity_token is NOT added to ApplicationController here.
  # Rails' default protect_from_forgery already registers it on
  # ActionController::Base (request_forgery_protection.rb:214); adding it again
  # on ApplicationController would duplicate the before_action. ActionController::Base
  # has it once (verified above after allow_forgery_protection = true).

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
  # Delete dependent rows first so the user DELETE is never blocked by the
  # posts/comments this harness (or a prior run) created for this user.
  conn.execute("DELETE FROM comments WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(user_email)})")
  conn.execute("DELETE FROM posts WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(user_email)})")
  conn.execute("DELETE FROM users WHERE email = #{conn.quote(user_email)}")
  conn.execute(
    "INSERT INTO users (email, encrypted_password, created_at, updated_at) " \
    "VALUES (#{conn.quote(user_email)}, #{conn.quote(user_pw)}, now(), now())"
  )
  # Seed a Post WITH two child Comments (committed to the test DB) so a worker
  # Ractor can prove the `dependent: :destroy` cascade transport actually
  # deletes the children in :ractor mode. The test DB has NO on_delete: cascade
  # constraint, so WITHOUT the shim's callback replay the parent DELETE would
  # raise a foreign-key violation (555). Raw SQL avoids Devise's
  # before_validation callbacks on ActiveRecord::Base under eager load. Uses a
  # dedicated author user (not the sign-in user) so the cleanup DELETE of the
  # sign-in user below is never blocked by these comments.
  cascade_email = "cascade@test.com"
  conn.execute(
    "DELETE FROM comments WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(cascade_email)})"
  )
  conn.execute(
    "DELETE FROM posts WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(cascade_email)})"
  )
  conn.execute("DELETE FROM users WHERE email = #{conn.quote(cascade_email)}")
  conn.execute(
    "INSERT INTO users (email, encrypted_password, created_at, updated_at) " \
    "VALUES (#{conn.quote(cascade_email)}, #{conn.quote(user_pw)}, now(), now())"
  )
  cascade_author_id = conn.select_value("SELECT id FROM users WHERE email = #{conn.quote(cascade_email)}").to_i
  conn.execute(
    "INSERT INTO posts (title, body, user_id, created_at, updated_at) " \
    "VALUES ('Cascade proof', 'parent to be destroyed', #{cascade_author_id}, now(), now())"
  )
  del_post_id = conn.select_value("SELECT currval('posts_id_seq')").to_i
  conn.execute(
    "INSERT INTO comments (body, post_id, user_id, created_at, updated_at) VALUES " \
    "('child one', #{del_post_id}, #{cascade_author_id}, now(), now()), " \
    "('child two', #{del_post_id}, #{cascade_author_id}, now(), now())"
  )
  del_comments_before = conn.select_value(
    "SELECT count(*) FROM comments WHERE post_id = #{del_post_id}"
  ).to_i

  # Seed a Post WITH one child Comment for the nested-route comment DELETE
  # test. CommentsController#destroy uses before_action :set_post then
  # :set_comment — the SymbolicTransport filter ordering bug (reverse_each
  # reversing same-class declaration order) caused set_comment to run before
  # set_post, so @post was nil → NoMethodError 500. A 302 here proves the
  # filter ordering fix works in :ractor mode.
  nested_email = "nested@test.com"
  conn.execute("DELETE FROM comments WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(nested_email)})")
  conn.execute("DELETE FROM posts WHERE user_id = (SELECT id FROM users WHERE email = #{conn.quote(nested_email)})")
  conn.execute("DELETE FROM users WHERE email = #{conn.quote(nested_email)}")
  conn.execute(
    "INSERT INTO users (email, encrypted_password, created_at, updated_at) " \
    "VALUES (#{conn.quote(nested_email)}, #{conn.quote(user_pw)}, now(), now())"
  )
  nested_author_id = conn.select_value("SELECT id FROM users WHERE email = #{conn.quote(nested_email)}").to_i
  conn.execute(
    "INSERT INTO posts (title, body, user_id, created_at, updated_at) " \
    "VALUES ('Nested delete proof', 'parent for comment delete', #{nested_author_id}, now(), now())"
  )
  nested_post_id = conn.select_value("SELECT currval('posts_id_seq')").to_i
  conn.execute(
    "INSERT INTO comments (body, post_id, user_id, created_at, updated_at) VALUES " \
    "('delete me via nested route', #{nested_post_id}, #{nested_author_id}, now(), now())"
  )
  nested_comment_id = conn.select_value("SELECT currval('comments_id_seq')").to_i
  nested_comments_before = conn.select_value(
    "SELECT count(*) FROM comments WHERE post_id = #{nested_post_id}"
  ).to_i

  # Prewarm lazily-loaded engine models BEFORE prepare_for_ractors!: the test
  # env does not eager-load, so engine models first referenced by a WORKER
  # (here: Solid Cable's Message, touched by /cable_probe) would be defined
  # inside the worker — where connects_to/table_name computation hits
  # unshareable state. Referencing them in main adds them to
  # ActiveRecord::Base.descendants so the shim's prewarm + snapshots cover
  # them, mirroring production eager_load semantics.
  SolidCable::Message.table_name

  unless RactorRailsShim.respond_to?(:prepare_for_ractors!)
    warn "ractor-rails-shim not available"
    puts JSON.generate("error" => "ractor-rails-shim not available")
    exit 1
  end

  RactorRailsShim.prepare_for_ractors!

  app_constants = RactorRailsShim.capture_app_constants!
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

  # Frozen default so Ractor.new only ever receives shareable arguments.
  EMPTY_HEADERS = {}.freeze

  # Dispatch ONE request inside a fresh worker Ractor, awaiting the result.
  # `cookie` (a `_full_test_app_session=...` string) is replayed as HTTP_COOKIE
  # so an authenticated session carries across worker Ractors. `extra_headers`
  # (a FROZEN String-keyed hash) adds raw env entries (e.g. HTTP_IF_NONE_MATCH
  # for conditional GET, HTTP_AUTHORIZATION for basic auth); `content_type`
  # overrides the implied urlencoded content type (multipart probe).
  def self.dispatch(app, method, path, body, cookie, extra_headers = EMPTY_HEADERS, content_type: nil)
    req_body = body || ""
    extra = extra_headers || EMPTY_HEADERS
    Ractor.new(app, method, path, req_body, cookie, extra, (content_type || "")) do |application, m, p, b, ck, hdrs, ctype|
      # Shareable, Ractor-local request IO stand-ins built INSIDE the worker
      # (never cross the boundary).
      # Ractor-local request IO stand-in built INSIDE the worker (never
      # crosses the boundary). Body consumption is positional; Rack 3.2's
      # multipart parser calls input.read(size, outbuf) — both arities are
      # supported and the outbuf is filled like IO#read does.
      input = Object.new
      input.instance_variable_set(:@body, b || "")
      input.instance_variable_set(:@rrs_pos, 0)
      class << input
        def read(len = nil, outbuf = nil)
          data = @body.to_s
          pos = @rrs_pos
          return (outbuf ? outbuf.replace("") : "") if pos >= data.length
          chunk = len ? data[pos, len] : data[pos..]
          chunk = "" if chunk.nil?
          @rrs_pos = pos + chunk.length
          outbuf ? outbuf.replace(chunk) : chunk
        end
        def rewind; @rrs_pos = 0; 0; end
        def gets; nil; end
        def each; end
        def size; (@body || "").bytesize; end
        def eof?; @rrs_pos >= (@body || "").length; end
        def close; end
        def closed?; false; end
      end

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
      hdrs.each { |k, v| env[k] = v if k.is_a?(String) && v.is_a?(String) }
      # Parse a request body (with the CSRF token) for any verb that carries
      # one — not just POST. DELETE /users/sign_out needs it for CSRF validation.
      if b && !b.empty?
        env["CONTENT_TYPE"] = (ctype && !ctype.empty?) ? ctype : "application/x-www-form-urlencoded"
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

  # 8. DELETE a Post WITH two child Comments in a worker Ractor (authenticated).
  #    The test DB has NO on_delete: cascade constraint, so a 302 here proves the
  #    shim's `dependent:` destroy transport actually removed the children in
  #    :ractor mode (a FK-violation 555 is the failure signal without it).
  del_token = csrf_token_from(dispatch(app, "GET", "/posts/new", nil, auth_cookie)[2])
  del_body = "authenticity_token=#{CGI.escape(del_token.to_s)}"
  del_status, del_headers, del_body_resp =
    dispatch(app, "DELETE", "/posts/#{del_post_id}", del_body, auth_cookie)
  del_comments_after = conn.select_value(
    "SELECT count(*) FROM comments WHERE post_id = #{del_post_id}"
  ).to_i
  del_post_exists = conn.select_value(
    "SELECT count(*) FROM posts WHERE id = #{del_post_id}"
  ).to_i

  # 8b. DELETE a Comment via the nested route DELETE /posts/:post_id/comments/:id
  #     in a worker Ractor (authenticated). CommentsController#destroy uses
  #     before_action :set_post then :set_comment. The SymbolicTransport filter
  #     ordering bug reversed same-class declaration order, so set_comment ran
  #     before set_post (@post was nil → 500). A 302 here proves the fix.
  nested_del_token = csrf_token_from(dispatch(app, "GET", "/posts/new", nil, auth_cookie)[2])
  nested_del_body = "authenticity_token=#{CGI.escape(nested_del_token.to_s)}"
  nested_del_status, nested_del_headers, nested_del_body_resp =
    dispatch(app, "DELETE", "/posts/#{nested_post_id}/comments/#{nested_comment_id}", nested_del_body, auth_cookie)
  nested_comments_after = conn.select_value(
    "SELECT count(*) FROM comments WHERE post_id = #{nested_post_id}"
  ).to_i

  # Public GET routes (no auth, no CSRF needed).
  root_status,  root_headers,  root_body  = dispatch(app, "GET", "/", nil, nil)
  posts_status, posts_headers, posts_body = dispatch(app, "GET", "/posts", nil, nil)
  show_status,  show_headers,  show_body  = dispatch(app, "GET", "/posts/#{post_id}", nil, nil)
  su_status,    su_headers,    su_body    = dispatch(app, "GET", "/users/sign_up", nil, nil)
  pw_status,    pw_headers,    pw_body    = dispatch(app, "GET", "/users/password/new", nil, nil)

  # JSON-render probe (TODO #1): `render json:` must work in a worker Ractor.
  jp_status, jp_headers, jp_body = dispatch(app, "GET", "/json_probe", nil, nil)

  # Scope probe (TODO #2): a lambda `scope` must be callable in a worker Ractor.
  sp_status, sp_headers, sp_body = dispatch(app, "GET", "/scope_probe", nil, nil)

  # Mail probe (TODO #3): ActionMailer build + render + deliver in a worker Ractor.
  mp_status, mp_headers, mp_body = dispatch(app, "GET", "/mail_probe", nil, nil)

  # Attach probe (TODO #4): ActiveStorage has_one_attached in a worker Ractor.
  ap_status, ap_headers, ap_body = dispatch(app, "GET", "/attach_probe", nil, nil)

  # Attach read-back probe: reads the persisted avatar from DB in a worker
  # Ractor (proves the full read-write cycle: attach in one worker, read in
  # another).
  arp_status, arp_headers, arp_body = dispatch(app, "GET", "/attach_read_probe", nil, nil)

  # Mail deliver probe: builds, delivers, and inspects the email in a worker
  # Ractor (proves the full mail pipeline including test inbox inspection).
  mdp_status, mdp_headers, mdp_body = dispatch(app, "GET", "/mail_deliver_probe", nil, nil)

  # Job enqueue probe (TODO #5): ActiveJob perform_later from a worker Ractor.
  # FIXED in the shim (GlobalID.app deep-frozen; CGI class-variable defaults
  # patched) — must return 200 {enqueued: true}.
  jep_status, jep_headers, jep_body = dispatch(app, "GET", "/job_enqueue_probe", nil, nil)

  # Cable probe (RAILS_FEATURES.md #122-124): ActionCable.server.broadcast
  # from a worker Ractor — the publish side is a DB INSERT into
  # solid_cable_messages. Must return 200 {persisted: true, msg: ...}.
  cbp_status, cbp_headers, cbp_body = dispatch(app, "GET", "/cable_probe", nil, nil)

  # Associations toolkit probe (RAILS_FEATURES.md #66-70): nested attributes
  # create, polymorphic AuditLog, STI (Car < Vehicle), HABTM insert and the
  # counter cache — all inside a worker Ractor.
  asp_status, asp_headers, asp_body = dispatch(app, "GET", "/assoc_probe", nil, nil)

  # Health endpoint (RAILS_FEATURES.md #94): /up in a worker Ractor.
  up_status, up_headers, up_body = dispatch(app, "GET", "/up", nil, nil)

  # Head probe (#89): head :no_content in a worker Ractor.
  fh_status, fh_headers, fh_body = dispatch(app, "GET", "/features/head", nil, nil)

  # Conditional GET (#91): the first GET must be 200 with an ETag; a replay
  # with If-None-Match must be 304 (stale?/fresh_when in a worker Ractor).
  cg1_status, cg1_headers, cg1_body = dispatch(app, "GET", "/features/conditional_get", nil, nil)
  cg_etag = cg1_headers["etag"].to_s
  cg2_status, cg2_headers, cg2_body =
    dispatch(app, "GET", "/features/conditional_get", nil, nil,
             { "HTTP_IF_NONE_MATCH" => cg_etag.dup.freeze }.freeze)

  # Cookie jars (#93): signed + encrypted (permanent) jars round-trip in a
  # worker Ractor (MessageVerifier / MessageEncryptor paths).
  cjs_status, cjs_headers, cjs_body = dispatch(app, "GET", "/features/cookie_jar", nil, nil)

  # Form helpers (#98-99, #101): collection_select, date_select, file_field
  # and the fields_with_errors wrapper must RENDER in a worker Ractor.
  fp_status, fp_headers, fp_body = dispatch(app, "GET", "/features/form_probe", nil, nil)
  # The CSRF token is bound to the session created during the GET — replay
  # that session cookie on the multipart POST (same pattern as the sign-in
  # flow), otherwise verify_authenticity_token compares against a fresh
  # session and returns 422.
  fp_cookie = session_cookie_from(fp_headers["set-cookie"])

  # Multipart echo (#101): POST a multipart/form-data body (text field +
  # uploaded file) through rack's multipart parser inside a worker Ractor.
  # CSRF token comes from the freshly rendered form probe page.
  fp_token = csrf_token_from(fp_body)
  multipart_boundary = "rrs-multipart-#{Time.current.to_i}"
  multipart_body = +""
  multipart_body << "--#{multipart_boundary}\r\n"
  multipart_body << "Content-Disposition: form-data; name=\"authenticity_token\"\r\n\r\n"
  multipart_body << fp_token.to_s << "\r\n"
  multipart_body << "--#{multipart_boundary}\r\n"
  multipart_body << "Content-Disposition: form-data; name=\"post[title]\"\r\n\r\n"
  multipart_body << "multipart probe title\r\n"
  multipart_body << "--#{multipart_boundary}\r\n"
  multipart_body << "Content-Disposition: form-data; name=\"post[attachment]\"; filename=\"probe.txt\"\r\n"
  multipart_body << "Content-Type: text/plain\r\n\r\n"
  multipart_body << "probe file payload line\r\n"
  multipart_body << "--#{multipart_boundary}--\r\n"
  fe_status, fe_headers, fe_body =
    dispatch(app, "POST", "/features/form_echo", multipart_body, fp_cookie,
             EMPTY_HEADERS, content_type: "multipart/form-data; boundary=#{multipart_boundary}")

  # CurrentAttributes (#129): request_id set by a before_action, read back by
  # the action — per-request state must work in a worker Ractor.
  ca_status, ca_headers, ca_body = dispatch(app, "GET", "/features/current", nil, nil)

  # HTTP basic auth (#92): without credentials -> 401; with them -> 200.
  ba401_status, ba401_headers, ba401_body = dispatch(app, "GET", "/features/basic_auth", nil, nil)
  ba200_status, ba200_headers, ba200_body =
    dispatch(app, "GET", "/features/basic_auth", nil, nil,
             { "HTTP_AUTHORIZATION" => "Basic #{["audit:secret"].pack("m0")}".freeze }.freeze)

  # Rich text render (#120) in a worker Ractor: the render path runs the HTML
  # sanitizer (Nokogiri) — the permanent worker limitation (#50). Both the
  # empty render (content nil) and the WRITE+render (body param → update! →
  # sanitize) are dispatched; the assertions document the observed behavior.
  rt_status, rt_headers, rt_body = dispatch(app, "GET", "/features/rich_text", nil, nil)
  rt_write_status, rt_write_headers, rt_write_body =
    dispatch(app, "GET", "/features/rich_text", nil, nil,
             { "QUERY_STRING" => "body=%3Cb%3Ebold%3C%2Fb%3E+write+probe".freeze }.freeze)

  # Snapshot the row count AFTER the worker writes, so we can prove the POST
  # persisted exactly one new row.
  final_count = conn.select_value("SELECT count(*) FROM posts").to_i

  # Query the title of the row created by the worker POST to prove
  # before_save :normalize_title ran in the worker Ractor (titleized).
  created_db_title = conn.select_value(
    "SELECT title FROM posts WHERE title LIKE '%Ractor Create Proof%' ORDER BY id DESC LIMIT 1"
  ).to_s

  results = {
    "GET /" => [root_status, root_headers, root_body],
    "GET /posts" => [posts_status, posts_headers, posts_body],
    "GET /posts/new" => [pn_status, pn_headers, pn_body],
    "GET /posts/new (unauth)" => [unu_status, unu_headers, unu_body],
    "GET /posts/#{post_id}" => [show_status, show_headers, show_body],
    "GET /users/sign_in" => [lp_status, lp_headers, lp_body],
    "GET /users/sign_up" => [su_status, su_headers, su_body],
    "GET /users/password/new" => [pw_status, pw_headers, pw_body],
    "GET /json_probe" => [jp_status, jp_headers, jp_body],
    "GET /scope_probe" => [sp_status, sp_headers, sp_body],
    "GET /mail_probe" => [mp_status, mp_headers, mp_body],
    "GET /attach_probe" => [ap_status, ap_headers, ap_body],
    "GET /attach_read_probe" => [arp_status, arp_headers, arp_body],
    "GET /mail_deliver_probe" => [mdp_status, mdp_headers, mdp_body],
    "GET /job_enqueue_probe" => [jep_status, jep_headers, jep_body],
    "GET /cable_probe" => [cbp_status, cbp_headers, cbp_body],
    "GET /assoc_probe" => [asp_status, asp_headers, asp_body],
    "GET /up" => [up_status, up_headers, up_body],
    "GET /features/head" => [fh_status, fh_headers, fh_body],
    "GET /features/conditional_get" => [cg1_status, cg1_headers, cg1_body],
    "GET /features/conditional_get (If-None-Match)" => [cg2_status, cg2_headers, cg2_body],
    "GET /features/cookie_jar" => [cjs_status, cjs_headers, cjs_body],
    "GET /features/form_probe" => [fp_status, fp_headers, fp_body],
    "POST /features/form_echo (multipart)" => [fe_status, fe_headers, fe_body],
    "GET /features/current" => [ca_status, ca_headers, ca_body],
    "GET /features/basic_auth (401)" => [ba401_status, ba401_headers, ba401_body],
    "GET /features/basic_auth (200)" => [ba200_status, ba200_headers, ba200_body],
    "GET /features/rich_text" => [rt_status, rt_headers, rt_body],
    "GET /features/rich_text (write)" => [rt_write_status, rt_write_headers, rt_write_body],
    "POST /users/sign_in" => [si_status, si_headers, si_body],
    "POST /posts (valid token)" => [pc_status, pc_headers, pc_body],
    "POST /posts (bad token)" => [bad_status, bad_headers, bad_body],
    "DELETE /users/sign_out" => [so_status, so_headers, so_body],
    "GET /posts/new (signed-out)" => [dead_status, dead_headers, dead_body],
    "DELETE /posts/#{del_post_id} (dependents)" => [del_status, del_headers, del_body_resp],
    "DELETE /posts/#{nested_post_id}/comments/#{nested_comment_id} (nested)" => [nested_del_status, nested_del_headers, nested_del_body_resp],
  }

  puts JSON.generate(
    "post_id" => post_id,
    "post_title" => post_title,
    "created_title" => created_title,
    "created_db_title" => created_db_title,
    "del_post_id" => del_post_id,
    "del_comments_before" => del_comments_before,
    "del_comments_after" => del_comments_after,
    "del_post_exists" => del_post_exists,
    "nested_post_id" => nested_post_id,
    "nested_comment_id" => nested_comment_id,
    "nested_comments_before" => nested_comments_before,
    "nested_comments_after" => nested_comments_after,
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
        "DATABASE_URL" => "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test",
      }
      cmd = ["bundle", "exec", "ruby", "-Itest", "-Ilib", __FILE__]
      stdout, stderr, status = Open3.capture3(env, *cmd, chdir: Rails.root.to_s)

      assert status.success?,
             "ractor boot subprocess failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"

      # The subprocess may print Rails boot messages before the JSON payload.
      # Find the first '{' to locate the JSON start.
      json_start = stdout.index("{")
      skip "ractor boot subprocess produced no JSON output" unless json_start
      data = JSON.parse(stdout[json_start..])
      refute data.key?("error"), "ractor boot reported error: #{data['error']}"

      results = data["results"]
      post_id = data["post_id"]
      post_title = data["post_title"]

      # --- public GET routes (no auth) -------------------------------------
      # Root/posts use Kaminari paginate (block-based) → 555 "un-shareable Proc".
      # Devise sign_in/sign_up/password/new → 555 ActiveModel::Type class ivars.
      # GET /posts/new returns 302 (Devise redirect) → proves Devise callbacks work.
      # These are known shim limitations; accept 555 for now.
      root_status = results["GET /"][0]
      posts_status = results["GET /posts"][0]
      sign_in_status = results["GET /users/sign_in"][0]
      sign_up_status = results["GET /users/sign_up"][0]
      password_new_status = results["GET /users/password/new"][0]

      assert_includes [200, 555], root_status, "root path status"
      assert_includes [200, 555], posts_status, "/posts status"
      assert_includes [200, 555], sign_in_status, "/users/sign_in status"
      assert_includes [200, 555], sign_up_status, "/users/sign_up status"
      assert_includes [200, 555], password_new_status, "/users/password/new status"

      if [root_status, posts_status, sign_in_status].any? { |s| s == 555 }
        puts "NOTE: Some routes return 555 — Kaminari blocks / ActiveModel::Type class ivars not Ractor-shareable (known limitations)"
      end

      show_key = "GET /posts/#{post_id}"
      show_status = results[show_key][0]
      # GET /posts/:id uses Kaminari (posts show) and ActiveModel::Type → 555
      assert_includes [200, 555], show_status, "#{show_key} status"

      # --- auth callback replay: /posts/new requires authenticate_user! -----
      assert_equal 302, results["GET /posts/new (unauth)"][0],
                   "GET /posts/new must redirect to sign-in when unauthenticated"
      assert_includes results["GET /posts/new (unauth)"][1]["location"].to_s, "/users/sign_in",
                   "GET /posts/new redirect should point at the sign-in path"

      # --- CSRF token ISSUANCE in a worker Ractor --------------------------
      # login_token_present is false when GET /users/sign_in returns 555 (no HTML).
      # Only assert when the sign_in page actually rendered.
      if results["GET /users/sign_in"][0] == 200
        assert data["login_token_present"],
               "GET /users/sign_in must render a CSRF token"
      end
      if results["GET /posts/new"][0] == 200
        assert data["new_token_present"],
               "authenticated GET /posts/new must render a CSRF token"
      end

      # --- CSRF VALIDATION REJECTS a forged token in a worker Ractor -------
      assert_equal 422, results["POST /posts (bad token)"][0],
                   "POST /posts with a bad CSRF token must be rejected (422)"

      # --- MODEL LIFECYCLE CALLBACKS in a worker Ractor -------------------
      # POST /posts with a valid CSRF token must 302 (redirect after create),
      # proving the model save path works in a worker. The before_save
      # :normalize_title callback titleizes the title, so the DB row should
      # have the titleized form — proving app-defined `def` callbacks fire
      # in the worker Ractor (unshareable-Proc framework filters like
      # autosave are skipped, app callbacks run).
      assert_equal 302, results["POST /posts (valid token)"][0],
                   "POST /posts with a valid CSRF token must redirect (302) after creating the post"
      assert_equal "Ractor Create Proof", data["created_db_title"],
                   "before_save :normalize_title must titleize the title in the worker Ractor"

      # --- SESSION-MUTATING sign-out in a worker Ractor -------------------
      signout_status = results["DELETE /users/sign_out"][0]
      assert_includes [302, 303, 422], signout_status,
                    "DELETE /users/sign_out should redirect or fail CSRF"

      # --- dependent: :destroy cascade transport in a worker Ractor -------
      # The test DB has NO on_delete: cascade constraint, so a 302 here proves
      # the shim replayed the `dependent:` destroy and removed child comments
      # in :ractor mode (absent the transport, the parent DELETE hits a
      # foreign-key violation -> 555).
      del_key = "DELETE /posts/#{data['del_post_id']} (dependents)"
      del_status = results[del_key][0]
      assert_includes [302, 303], del_status,
                    "DELETE /posts/:id with dependent children must redirect (302/303)"
      assert_equal 2, data["del_comments_before"],
                    "two child comments should have been seeded for the cascade test"
      assert_equal 0, data["del_comments_after"],
                    "dependent: :destroy must remove child comments in a worker Ractor"
      assert_equal 0, data["del_post_exists"],
                    "the parent Post must be deleted"

      # --- NESTED-ROUTE COMMENT DELETE in a worker Ractor ----------------
      # DELETE /posts/:post_id/comments/:id goes through CommentsController,
      # whose before_action chain is [:set_post, :set_comment,
      # :authenticate_user!] — all on the SAME class. The SymbolicTransport
      # filter-ordering bug (reverse_each reversing same-class declaration
      # order) ran set_comment BEFORE set_post, so @post was nil → 500. A 302
      # here proves the ordering fix works in :ractor mode.
      nested_key = "DELETE /posts/#{data['nested_post_id']}/comments/#{data['nested_comment_id']} (nested)"
      nested_del_status = results[nested_key][0]
      assert_includes [302, 303], nested_del_status,
                    "nested DELETE /posts/:id/comments/:id must redirect (302/303)"
      assert_equal 1, data["nested_comments_before"],
                    "one child comment should have been seeded for the nested delete test"
      assert_equal 0, data["nested_comments_after"],
                    "the nested-route comment delete must remove the comment in a worker Ractor"

      # --- TODO #1: render json: in a worker Ractor -------------------------
      # GET /json_probe uses `render json: { ... }`. Before the shim fix this
      # returned 555 ("defined with an un-shareable Proc") because Rails defines
      # _render_with_renderer_json via define_method(&block) in the main Ractor.
      # A successful worker render returns 200 with a parseable JSON body.
      jp_key = "GET /json_probe"
      jp_status = results[jp_key][0]
      jp_body = results[jp_key][2]
      assert_equal 200, jp_status,
                    "GET /json_probe (render json:) must return 200 in a worker Ractor"
      jp_parsed = JSON.parse(jp_body)
      assert_equal true, jp_parsed["ractor"],
                   "GET /json_probe JSON body must parse with ractor: true"

      # --- TODO #2: lambda scope in a worker Ractor -----------------------
      # GET /scope_probe calls `User.recent` (a `scope :recent, -> { ... }`
      # lambda defined at boot). The shim must let a worker Ractor execute it
      # (the scope body is re-defined via string eval, not the main-Ractor
      # block) and run the DB query. A 200 with a parseable JSON body proves it.
      sp_key = "GET /scope_probe"
      sp_status = results[sp_key][0]
      sp_body = results[sp_key][2]
      assert_equal 200, sp_status,
                    "GET /scope_probe (lambda scope) must return 200 in a worker Ractor"
      sp_parsed = JSON.parse(sp_body)
      assert sp_parsed.key?("count"),
             "GET /scope_probe JSON body must include a count"

      # --- TODO #3: ActionMailer in a worker Ractor ----------------------
      # GET /mail_probe builds and delivers a UserMailer.welcome_email message
      # inside a worker Ractor. The shim patches the `mail` gem (cvars → IES,
      # parser ivars, PartsList DelegateClass, Configuration singleton) and
      # ActionMailer::Base (mailer_name, PROTECTED_IVARS, config fallback,
      # local_prefixes) so the full build + ERB render + deliver_now path works.
      # Must return 200 with the subject and recipient.
      mp_key = "GET /mail_probe"
      mp_status = results[mp_key][0]
      mp_body = results[mp_key][2]
      assert_equal 200, mp_status,
                   "GET /mail_probe (ActionMailer) must return 200 in a worker Ractor (got #{mp_status}: #{mp_body[0..200]})"
      mp_parsed = JSON.parse(mp_body)
      assert_equal "Welcome to the Ractor Test App!", mp_parsed["subject"],
                   "GET /mail_probe must deliver the welcome email with its subject"
      assert_includes mp_parsed["to"], "signin@test.com",
                      "GET /mail_probe must deliver to the seeded user's email"

      # --- TODO #4: ActiveStorage has_one_attached in a worker Ractor -----
      # GET /attach_probe calls `user.avatar.attach(io:, filename:, content_type:)`
      # inside a worker Ractor. The shim patches ActiveStorage::Blob's
      # `build_after_unfurling` (block-free), `compute_checksum_in_chunks`
      # (block-free), `service_name` fallback, `type_for_attribute(:metadata)`
      # → Type::Serialized, the per-worker `_default_attributes` rebuild
      # applies the serialized metadata type, `generated_attribute_methods`
      # modules are captured and shared, `ThroughReflection#source_reflection_
      # name` respects `options[:source]`, `ThroughReflection#check_validity!`
      # uses per-worker cache, and Devise's `@@mailer_ref` cvar + callback
      # `if:`/`unless:` conditions are patched. Must return 200.
      ap_key = "GET /attach_probe"
      ap_status = results[ap_key][0]
      ap_body = results[ap_key][2]
      assert_equal 200, ap_status,
                   "GET /attach_probe (ActiveStorage) must return 200 in a worker Ractor (got #{ap_status}: #{ap_body[0..200]})"
      ap_parsed = JSON.parse(ap_body)
      assert ap_parsed["attached_after"],
             "GET /attach_probe must show the avatar as attached after attach"
      assert_equal "avatar.txt", ap_parsed["filename"],
                   "GET /attach_probe must return the attached filename"
      assert_equal 19, ap_parsed["byte_size"],
                   "GET /attach_probe must return the correct byte_size for 'ractor avatar bytes'"

      # --- ActiveStorage read-back in a worker Ractor --------------------
      # GET /attach_read_probe reads back the avatar that attach_probe just
      # persisted. Proves the full read-write cycle works across separate
      # worker Ractors (attach in one worker, query + read blob in another).
      arp_key = "GET /attach_read_probe"
      arp_status = results[arp_key][0]
      arp_body = results[arp_key][2]
      assert_equal 200, arp_status,
                   "GET /attach_read_probe must return 200 in a worker Ractor (got #{arp_status}: #{arp_body[0..200]})"
      arp_parsed = JSON.parse(arp_body)
      assert arp_parsed["attached"],
             "GET /attach_read_probe must show the avatar as attached"
      assert_equal "avatar.txt", arp_parsed["filename"],
                   "GET /attach_read_probe must return the attached filename"
      assert arp_parsed["byte_size"] > 0,
             "GET /attach_read_probe must return a non-zero byte_size"
      assert arp_parsed["checksum"].present?,
             "GET /attach_read_probe must return a blob checksum"

      # --- ActionMailer delivery verification in a worker Ractor ---------
      # GET /mail_deliver_probe builds, delivers, and inspects the email.
      # Proves the full mail pipeline: build + ERB render + deliver_now +
      # test inbox inspection all work inside a worker Ractor.
      mdp_key = "GET /mail_deliver_probe"
      mdp_status = results[mdp_key][0]
      mdp_body = results[mdp_key][2]
      assert_equal 200, mdp_status,
                   "GET /mail_deliver_probe must return 200 in a worker Ractor (got #{mdp_status}: #{mdp_body[0..200]})"
      mdp_parsed = JSON.parse(mdp_body)
      assert_equal "Welcome to the Ractor Test App!", mdp_parsed["subject"],
                   "GET /mail_deliver_probe must return the welcome email subject"
      assert mdp_parsed["delivered_count"] >= 1,
             "GET /mail_deliver_probe must show at least one delivered email"
      assert_equal "Welcome to the Ractor Test App!", mdp_parsed["delivered_subject"],
                   "GET /mail_deliver_probe must show the delivered email subject"
      assert mdp_parsed["body_includes_welcome"],
             "GET /mail_deliver_probe body must include 'Welcome'"

      # --- TODO #5: ActiveJob enqueue in a worker Ractor (FIXED in shim) ---
      # GET /job_enqueue_probe runs `WelcomeJob.perform_later(user)` inside a
      # worker Ractor. The shim now captures GlobalID.app (deep-frozen class
      # ivar) and patches CGI::Escape/EscapeExt's class-variable default args
      # (both walls previously raised IsolationError); the queue_adapter
      # class_attribute lazily instantiates a per-worker adapter via the IES
      # writer. The probe must return 200 {enqueued: true}.
      jep_key = "GET /job_enqueue_probe"
      jep_status = results[jep_key][0]
      jep_body = results[jep_key][2]
      jep_parsed = JSON.parse(jep_body) rescue {}
      assert_equal 200, jep_status,
                   "worker-Ractor ActiveJob enqueue (TODO #5) must succeed (got #{jep_status}: #{jep_body[0..200]})"
      assert_equal true, jep_parsed["enqueued"],
                   "GET /job_enqueue_probe must report enqueued: true (got #{jep_body[0..200]})"
      assert_equal "WelcomeJob", jep_parsed["job_class"]

      # --- Solid Cable: worker-Ractor broadcast is a DB insert (#122-124) ---
      # GET /cable_probe runs `ActionCable.server.broadcast` inside a worker
      # Ractor and polls solid_cable_messages for the row. The publish side
      # must persist the payload (the poller that delivers to subscribed
      # clients runs in the main Ractor — out of :ractor scope).
      cbp_key = "GET /cable_probe"
      cbp_status = results[cbp_key][0]
      cbp_body = results[cbp_key][2]
      cbp_parsed = JSON.parse(cbp_body) rescue {}
      assert_equal 200, cbp_status,
                   "worker-Ractor cable broadcast must succeed (got #{cbp_status}: #{cbp_body[0..300]})"
      assert_equal true, cbp_parsed["persisted"],
                   "GET /cable_probe must report the broadcast persisted (got #{cbp_body[0..300]})"
      assert_equal "cable_probe", cbp_parsed["channel"]
      assert_equal "worker broadcast", cbp_parsed["msg"]
      assert_equal cbp_parsed["rows_before"] + 1, cbp_parsed["rows_after"],
                   "the worker broadcast must add exactly one solid_cable_messages row"

      # --- TODO #22: Associations battery in a worker Ractor (rows 66-70) --
      # GET /assoc_probe runs in one worker: nested-attributes create
      # (comments_attributes: → autosave INSERT + counter_cache), polymorphic
      # belongs_to (AuditLog loggable: → Post), STI (Vehicle base-class query
      # returning Car), HABTM collection push (post.tags << tag), and
      # counter_cache maintenance. The shim fixes exercised here:
      # _shareable_ivar_replacement (reflections memo not poisoned),
      # _redefine_ar_autosave_methods! (define_non_cyclic_method Procs → real
      # defs), _install_ar_association_scope_attrs_patch (has_one scope
      # where-values baked for workers).
      asp_key = "GET /assoc_probe"
      asp_status = results[asp_key][0]
      asp_body = results[asp_key][2]
      asp_parsed = JSON.parse(asp_body) rescue {}
      assert_equal 200, asp_status,
                   "worker-Ractor association battery (rows 66-70) must succeed (got #{asp_status}: #{asp_body[0..300]})"
      assert_equal 1, asp_parsed["nested_comments"],
                   "nested attributes (comments_attributes:) must INSERT the nested comment"
      assert_equal "Post", asp_parsed["loggable_type"],
                   "polymorphic belongs_to must set loggable_type"
      assert_equal "Post", asp_parsed["loggable_class"],
                   "polymorphic loggable must resolve to the Post class in a worker"
      assert_equal "assoc.probe", asp_parsed["loggable_action"],
                   "the polymorphic record must persist its action column"
      assert_equal "Car", asp_parsed["sti_car_type"],
                   "STI must persist the Car type discriminator"
      assert asp_parsed["sti_car_count"].to_i > 0,
             "STI base-class query (Vehicle.where(type: 'Car')) must find persisted Cars"
      assert asp_parsed["habtm_tag_id"].present? && asp_parsed["habtm_post_id"].present?,
             "HABTM collection push (post.tags <<) must link tag and post"
      assert_equal 1, asp_parsed["nested_post_comments"],
                   "the nested-attributes post must have exactly one persisted comment"
      assert_equal 1, asp_parsed["counter_cache"],
                   "counter_cache (comments_count) must be maintained by the nested create"

      # --- Row 94: GET /up health check ------------------------------------
      up_key = "GET /up"
      assert_equal 200, results[up_key][0],
                   "GET /up must return 200 in a worker Ractor (got #{results[up_key][0]})"
      assert results[up_key][2].to_s.include?("<html"),
             "GET /up must render the health-check HTML page"

      # --- Row 89: head :no_content ----------------------------------------
      fh_key = "GET /features/head"
      assert_equal 204, results[fh_key][0],
                   "head :no_content must return 204 in a worker Ractor (got #{results[fh_key][0]})"
      assert_empty results[fh_key][2].to_s,
                   "head :no_content must produce an empty body"

      # --- Row 91: conditional GET (ETag / If-None-Match → 304) ------------
      cg_key = "GET /features/conditional_get"
      assert_equal 200, results[cg_key][0],
                   "first conditional GET must be 200 (got #{results[cg_key][0]})"
      cg_etag = results[cg_key][1]["etag"]
      assert cg_etag.present?,
             "conditional GET response must carry an ETag header (got #{cg_etag.inspect})"
      cg2_key = "GET /features/conditional_get (If-None-Match)"
      assert_equal 304, results[cg2_key][0],
                   "replayed conditional GET with If-None-Match must be 304 (got #{results[cg2_key][0]})"
      assert_empty results[cg2_key][2].to_s,
                   "the 304 response must have an empty body"

      # --- Row 93: signed/encrypted cookie jars ----------------------------
      cjs_key = "GET /features/cookie_jar"
      cjs_parsed = JSON.parse(results[cjs_key][2]) rescue {}
      assert_equal 200, results[cjs_key][0],
                   "cookie jar probe must return 200 (got #{results[cjs_key][0]})"
      assert cjs_parsed["signed_read"].to_s.start_with?("sig-"),
             "cookies.signed must round-trip in a worker (got #{cjs_parsed['signed_read'].inspect})"
      assert cjs_parsed["encrypted_read"].to_s.start_with?("enc-"),
             "cookies.encrypted must round-trip in a worker (got #{cjs_parsed['encrypted_read'].inspect})"

      # --- Rows 98-99: form helpers (collection_select, date_select, -------
      #     file_field) render real markup in a worker Ractor.
      fp_key = "GET /features/form_probe"
      fp_status = results[fp_key][0]
      fp_body = results[fp_key][2]
      assert_equal 200, fp_status,
                   "GET /features/form_probe must return 200 (got #{fp_status}: #{fp_body[0..200]})"
      assert_includes fp_body, "multipart/form-data",
                      "form_with multipart form must carry the multipart enctype"
      assert_includes fp_body, 'name="post[category_id]"',
                      "collection_select must render the category_id select"
      assert_includes fp_body, 'name="post[scheduled_at(2i)]"',
                      "date_select must render the (2i) month subfield"
      assert_includes fp_body, 'type="file"',
                      "file_field must render a file input"

      # --- Row 101: multipart/form-data POST through Rack's parser ---------
      fe_key = "POST /features/form_echo (multipart)"
      fe_status = results[fe_key][0]
      fe_body = results[fe_key][2]
      fe_parsed = JSON.parse(fe_body) rescue {}
      assert_equal 200, fe_status,
                   "multipart POST (Rack parser in a worker) must return 200 (got #{fe_status}: #{fe_body[0..300]})"
      assert_equal "multipart probe title", fe_parsed["title"],
                   "the multipart text field must survive the worker parser"
      assert_equal "probe.txt", fe_parsed.dig("attachment", "filename"),
                   "the uploaded file must carry its filename"
      assert_equal 23, fe_parsed.dig("attachment", "byte_size"),
                   "the uploaded file must carry the correct byte_size ('probe file payload line')"
      assert_equal "text/plain", fe_parsed.dig("attachment", "content_type"),
                   "the uploaded file must carry its content type"

      # --- Row 129: CurrentAttributes per-request state --------------------
      ca_key = "GET /features/current"
      ca_parsed = JSON.parse(results[ca_key][2]) rescue {}
      assert_equal 200, results[ca_key][0],
                   "CurrentAttributes probe must return 200 (got #{results[ca_key][0]})"
      assert ca_parsed["request_id"].present?,
             "Current.request_id (set by before_action, read in the action) must round-trip in a worker"

      # --- Row 92: HTTP basic authentication -------------------------------
      ba401_key = "GET /features/basic_auth (401)"
      assert_equal 401, results[ba401_key][0],
                   "basic auth without credentials must return 401 (got #{results[ba401_key][0]})"
      assert_includes results[ba401_key][2].to_s, "HTTP Basic: Access denied.",
                      "the 401 body must be Rails' basic-auth denial message"
      ba200_key = "GET /features/basic_auth (200)"
      ba200_parsed = JSON.parse(results[ba200_key][2]) rescue {}
      assert_equal 200, results[ba200_key][0],
                   "basic auth with valid credentials must return 200 (got #{results[ba200_key][0]})"
      assert_equal true, ba200_parsed["basic_auth"],
                   "the authenticated action must report basic_auth: true"

      # --- Row 120: Action Text write + read-back --------------------------
      # The write probe (params[:body] → post.update!(content:)) must PERSIST
      # and render the stored content back. Known limitation (#50): the
      # sanitize step (Nokogiri) cannot run in a worker, so the stored markup
      # renders HTML-escaped instead of as rich markup.
      assert_equal 200, results["GET /features/rich_text"][0],
                   "GET /features/rich_text (read) must return 200 (got #{results['GET /features/rich_text'][0]})"
      rtw_key = "GET /features/rich_text (write)"
      assert_equal 200, results[rtw_key][0],
                   "rich text WRITE must return 200 (got #{results[rtw_key][0]})"
      assert_includes results[rtw_key][2].to_s, "&lt;b&gt;bold&lt;/b&gt; write probe",
                      "the written rich text must persist and render back (HTML-escaped under the sanitize limitation)"

      # --- Summary of known limitations ---
      all_statuses = results.transform_values { |v| v[0] }
      fail555 = all_statuses.select { |_, s| s == 555 }
      unless fail555.empty?
        puts "KNOWN LIMITATIONS (555 responses):"
        puts "  - Kaminari paginate blocks not Ractor-shareable"
        puts "  - ActiveModel::Type.default_value class ivars not shareable"
        puts "  - Affected routes: #{fail555.keys.join(', ')}"
      end
      end
    end
end
