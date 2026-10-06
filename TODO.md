# TODO — Full Rails-guides coverage audit

Companion to `RAILS_FEATURES.md` (rows 61–144). Every 🔲 row gets one item
here. Item types:

- **[CHECK]** — feature probably already works; add the exercising test/probe
  and flip the matrix row to ✅. No new app code expected.
- **[IMPLEMENT]** — add the missing app-side feature + test, then probe in
  `:ractor` mode (add a `/…_probe` route + dispatch in
  `test/integration/ractor_server_test.rb` when it's worker-reachable).
- **[VERIFY]** — run the probe/test; outcome decides: flip matrix row ✅,
  or move the row to Known limitations (⛔) with a workaround note.
- **[DECIDE]** — needs a design call (shim work vs documented exclusion).

Do them in priority order. When an item is done: flip the `RAILS_FEATURES.md`
row, tick it here, note the evidence (test file / probe status).

## P1 — likely on real request paths, highest value

1. **[DONE ✅] Worker-side validations (rows 1, 98) — fixed in the shim's
   callback-capture layer: the `set_callback` interceptor now captures
   validator-object filters (`validates` / `validates_with` →
   `ActiveModel::Validator` instances) as shareable descriptors
   `{validator-class-name, attributes, options, declaring-class}` and the
   SymbolicTransport rebuilds a fresh validator in the worker and calls
   `.validate(record)`; `:validate` added to DEFAULT_KINDS; phase parsing
   fixed for no-explicit-phase declarations (`validate :sym` was silently
   missed); `on:`/`except_on:` captured as context keys and gated on
   `validation_context`; callbacks with unresolvable Proc conditions are
   SKIPPED (fail-safe, never over-run); unfrozen validator constants
   (`LengthValidator::RESERVED_OPTIONS`, `ActiveModel::Error::CALLBACKS_OPTIONS`)
   deep-frozen at prepare; `ActiveModel::Name#i18n_keys`/`i18n_scope` made
   frozen-safe (error-message generation no longer FrozenErrors post-freeze).
   kino evidence: `/features/validations_probe` (invalid → false with
   `:body` errors, valid → true) + form_probe renders the
   `field_with_errors` wrapper in workers. Known residual gaps: validators
   with unresolvable user-Proc if:/unless: don't replay in workers; raw
   `__callbacks[:validate]` reads in workers still show the empty
   class-attribute fallback (replay-based, raw chain inspection only).
2. **[DONE ✅]** AR `enum` (row 65) — kino `/features/enum_probe`: worker-side
   `state` default casts to `"draft"` through the replayed EnumType (was raw
   `0`), `moderated!`/`moderated?` run as real defs (was "un-shareable Proc"),
   `Post.states` + `Post.moderated`/`Post.not_draft` scopes query, invalid
   assignment raises ArgumentError like main. Shim fixes: real defs via
   `_redefine_ar_enum_methods!`; shareable pending-mod Structs via
   `_share_ar_pending_attribute_modifications!` (undecoratable enum
   decoration Proc → `RactorRailsShim::EnumTypeDecorator`, run BEFORE the
   model-snapshot capture that seeds `SHAREABLE_PENDING_ATTR_MODS`).
3. **[DONE ✅]** AR dirty tracking (row 73) — comment_test asserts the full
   lifecycle (`changed?` on new + mutated records, `changes` [old, new]
   pair, post-save `saved_changes`); kino `/features/dirty_probe`: identical
   values in a worker (mutation → save). No shim changes needed.
4. **[CHECK] AR batch processing (row 62) — switch `posts:stats` to
   `find_each`; run in a worker (rake in kino context or a probe route).
5. **[CHECK] Aggregates completion (row 63) — add `group`/`having`/`pluck`/
   `exists?` to `posts:stats` or a test.
6. **[CHECK] Grouping / distinct (row 64) — same probe as #4.
7. **[DONE ✅]** Counter cache in workers (row 70) — explicit assert: create a
   comment from a worker probe, `post.comments_count` incremented (the SQL
   `UPDATE posts SET comments_count...` runs on the worker's connection).
8. **[CHECK] `signed_id` explicitly (row 75) — `Post.first.signed_id` +
   `Post.find_signed` round-trip in a worker probe (signing uses
   MessageVerifier — implied ✅ via Devise, make it explicit).
9. **[CHECK] `insert_all` / `upsert_all` (row 76) — bulk-create tags in a
   worker probe.
10. **[DONE ✅]** Nested attributes (row 69) — accept
   `comments_attributes` on Post in the create flow + form; probe in worker.
11. **[DONE ✅]** Polymorphic association (row 66) — `AuditLog` with
    `loggable` (polymorphic) or Tag `taggable`; migrate + test + worker probe.
12. **[DONE ✅]** Conditional GET (row 91) — `fresh_when @post` on
    `posts#show`; worker probe must return 304 on matching ETag.
13. **[DONE ✅]** Cookie jars (row 93) — set/read `cookies.permanent.signed` +
    `cookies.encrypted` in a controller; worker probe (encrypted cookie jar =
    MessageEncryptor — main suspect).
14. **[DONE ✅]** `/up` health endpoint (row 94) — dispatch
    `GET /up` in the ractor test; expect 200.
15. **[DONE ✅]** Collection partials (row 96) — `posts/index` renders
    `render partial: "post", collection: @posts` instead of the manual loop
    (keep the russian-doll `cache` inside the partial).
16. **[DONE ✅]** Plain multipart file upload (row 101) — `file_field` on a
    form posting a small file to an AS attach endpoint (or plain params echo);
    rack-multipart parsing in workers.
17. **[DONE ✅]** `date_select` / `collection_select` (row 99) — add a scheduled
    date + category select to the post form; worker render probe.
18. **[CHECK] Job `retry_on` / `discard_on` (row 107) — add a flaky job;
    test enqueues + retry bookkeeping with the test adapter; worker probe for
    enqueue.
19. **[CHECK] Enqueue options (row 108) — `WelcomeJob.set(wait: 5.seconds,
    queue: "low").perform_later` from worker; `assert_enqueued_with` in test.
20. **[CHECK] Mailer interceptors (row 113) — register a test interceptor
    (adds a header); assert in `email_delivery_test`; worker-side intercept.
21. **[DONE ✅]** AS `CurrentAttributes` (row 129) — set `Current.user` in a
    before_action, read in a worker-rendered view; verify reset semantics
    (per-Ractor? per-thread?) in kino.
22. **[CHECK] Time zones (row 131) — `config.time_zone = "Europe/Berlin"`;
    render `in_time_zone` from a worker view probe.
23. **[CHECK] `Rails.error` reporting (row 133) — rescue_from already
    handles app errors; verify a worker-raised error reaches the ErrorReporter
    + log subscriber path.
24. **[DONE] Action Text (rows 120–121) — `has_rich_text :content` on Post
    (migration 20261006000007); write + sanitize + render verified in the
    MAIN ractor (`test/controllers/rich_text_test.rb`). Worker-side render
    probe still pending — expect the Nokogiri sanitizer wall (same class as
    #50); if confirmed in the kino: matrix row gains a worker-side ⛔ note.
25. **[DONE] Action Cable in `:ractor` kino (rows 122–124) — `solid_cable`
    adopted (DB-backed, PG stack, no Redis); all envs point at the primary
    DB without `connects_to` (pool spec-name rationale in config/cable.yml).
    Worker broadcast verified in the kino (`GET /cable_probe` 200, persisted
    row; shim gained per-Ractor cable server + SolidCable configuration).
    Connection semantics (row 122) stay main-Ractor-scope.
26. **[DONE] Action Mailbox (rows 117–119) — `ApplicationMailbox` routes
    `:all => :inbox`; `InboxMailbox` records a polymorphic AuditLog;
    `test/mailboxes/inbox_mailbox_test.rb` uses
    `receive_inbound_email_from_mail` (the create_ variant does NOT route).
27. **[IMPLEMENT] Real production cache store (rows 45–47 caveat) —
    `production.rb` sets `perform_caching = true` but configures no
    `cache_store`, and no `solid_cache` gem is bundled → the store defaults
    to `:null_store`, so the `:ractor` kino caching probes exercise the
    no-op path (they don't fail, but they don't cache either). Add
    `solid_cache` (the Rails 8 default stack, DB-backed → fits the PG
    setup) and re-verify fragment/russian-doll/low-level caching in kino.

## P2 — toolkit depth

1. **[CHECK] Optimistic locking (row 71) — `lock_version` on Post;
    concurrent-update `ActiveRecord::StaleObjectError` test.
2. **[CHECK] Pessimistic locking (row 72) — `Post.with_lock` in a job.
3. **[CHECK] `normalizes` (row 74) — `normalizes :email, with: ->(v) { v.strip.downcase }`
    on User (norm Procs must be shareable — same class as scope lambdas).
4. **[DONE ✅]** STI or delegated types (row 67) — smallest: `Comment::Admin`? Prefer
    a `Vehicle/Car`-style demo on a throwaway model.
5. **[DONE ✅]** HABTM / `has_one :through` (row 68) — tiny join-table model.
6. **[CHECK] `default_scope` / `unscoped` (row 78) — on Category.
7. **[CHECK] `strict_loading` (row 79) — flip on a probe action, assert
    N+1 raises.
8. **[CHECK] `load_async` (row 77) — `Post.load_async` in a worker
    (futures + thread pool — the same Thread-in-Ractor class as the async
    job adapter).
9. **[IMPLEMENT] Advanced migrations (row 83) — one migration exercising
    `reversible` + FK + check constraint; `db:rollback` then re-migrate.
10. **[CHECK] Postgres types (row 82) — jsonb column + array column on
    AuditLog; worker-side jsonb query.
11. **[CHECK] Composite PKs / multiple DBs (rows 80–81) — low; document
    "single-DB kino" if skipped.
12. **[CHECK] Custom form builders / `fields_for` (row 97) — comment
    sub-form on posts.
13. **[CHECK] `fields_with_errors` (row 98) — submit invalid post form;
    assert wrapper div.
14. **[CHECK] Text helpers (row 100) — `truncate` + `pluralize` in the
    index view (NOT `highlight`/`excerpt` — they use `sanitize`-adjacent
    Nokogiri paths? verify before adding).
15. **[CHECK] `head` / custom statuses (row 89) — probe route returning
    `head :no_content`.
16. **[CHECK] HTTP auth (row 92) — `http_basic_authenticate_with` on a
    probe controller; worker probe.
17. **[CHECK] Mailer delivery methods (row 115) — configure SMTP settings
    shape (delivery won't actually send; assert Mail message build).
18. **[CHECK] Mailer callbacks (row 116) — `after_action` in UserMailer.
19. **[CHECK] Storage services (rows 125–127) — public service + blob
    download/proxy route probe; mirror/encrypted service optional-low.
20. **[CHECK] Analyzers / `analyze_later` (row 126) — attach a text blob,
    assert metadata extraction.
21. **[CHECK] Durations / time math (row 132) — `2.days.ago`-style scopes
    in tests (likely already passing implicitly).
22. **[CHECK] Tagged / broadcast logging (row 134) — `config.log_tags` +
    `Rails.logger.tagged` in a worker probe.
23. **[CHECK] force_ssl / security headers (rows 136–137) — assert
    headers in a controller test; kino terminates TLS outside, so this is
    config-level.
24. **[CHECK] `config.x` / `config_for` (row 138) — add
    `config.x.audit.flag` + `config/audit.yml`; read in a worker probe.

## P3 — niche / low priority

51. **[CHECK] Turbo Frames / Streams server-side (rows 104–105) —
    respond with a `turbo_stream` template on a probe; no JS needed to
    verify server rendering.
52. **[CHECK] `dom_id` (row 102) — used by Turbo; trivial render probe.
53. **[CHECK] Localized views (row 103) — add `index.en.html.erb` alias
    pattern probe.
54. **[CHECK] `ActionController::Live` SSE (row 95) — probe route streaming
    two events; check per-request thread + Ractor interaction.
55. **[CHECK] Custom job serializers (row 109) — serialize a
    Struct/GeoPoint argument.
56. **[CHECK] Solid Queue (row 110) — bundle + run dispatcher as a second
    process; enqueue from a worker; assert job performs. Biggest remaining
    backend question.
57. **[CHECK] Parallel testing (row 140) — `bin/rails test` with
    `PARALLEL_WORKERS=2` (processes fork, not Ractors — should be safe).
58. **[CHECK] CLI niceties (rows 141–143) — `rails runner "puts 1"`,
    `rails dbconsole` smoke, `assets:precompile` once.
59. **[CHECK] Engines (row 144) — mount a minimal isolated engine; probe a
    route through it in `:ractor` mode.
60. **[CHECK] Encrypted storage service (row 128) — optional.

## Known limitations (NOT todos)

- **#50 sanitize / simple_format / strip_tags (Nokogiri)** — permanent;
  workaround documented in `RAILS_FEATURES.md` ("Living without Nokogiri").
- **#90 `around_action`** — shim SymbolicTransport skips `:around` filters.
  Either becomes a shim project (replay-as-wrap execution) or stays a
  documented exclusion. Decided by the [DECIDE] outcome above.
- **Direct-upload JS client** (#40) — app deliberately ships no JS tags.
- **Browser-based system tests** (#56) — rack_test only; wiring
  selenium + real browser is orthogonal to Ractors.

## Working rules

- Every [CHECK]/[IMPLEMENT] that touches a worker-reachable path gets a
  `:ractor` probe: add the route, dispatch it in
  `test/integration/ractor_server_test.rb`, assert 200 + content (or the
  documented 422/302/304).
- New walls → shim fix + regression spec + `CHANGELOG.md` entry (follow the
  caching/CGI commits), then flip the matrix row.
- Keep `RAILS_FEATURES.md` Summary counts in sync with the rows after every
  batch of flips.
