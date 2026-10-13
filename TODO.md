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
4. **[DONE ✅]** AR batch processing (row 62) — `posts:stats` now iterates
   with `find_each(batch_size: 100)` (Titled census; `recount_comments`
   already used find_each); kino `/features/batch_probe`: find_each /
   find_in_batches / in_batches each visit every post in a worker.
5. **[DONE ✅]** Aggregates completion (row 63) — post_test asserts
   sum/average/minimum/maximum/pluck/pick/ids/exists? (incl. empty-scope
   false); kino `/features/aggregate_probe`: same values in a worker.
6. **[DONE ✅]** Grouping / distinct (row 64) — post_test asserts
   `group(:state).count`, `having("COUNT(id) > 0")`, `distinct.count(:title)`;
   kino `/features/aggregate_probe`: identical group/having sizes + distinct
   count in a worker.
7. **[DONE ✅]** Counter cache in workers (row 70) — explicit assert: create a
   comment from a worker probe, `post.comments_count` incremented (the SQL
   `UPDATE posts SET comments_count...` runs on the worker's connection).
8. **[DONE ✅]** `signed_id` explicitly (row 75) — kino
   `/features/signed_id_probe`: worker-side `signed_id(expires_in:)` →
   `find_signed` round-trip, garbage signature → `nil` / `InvalidSignature` for
   `find_signed!`. Exercising it surfaced a real shim gap (fixed in shim
   0.4.2): the lazily-built `active_record/signed_id` verifier codec could not
   be built by workers (NoOpProc'd rotation/secret generator on the frozen
   graph), so main pre-warms it during `prepare_for_ractors!`.
9. **[DONE ✅]** `insert_all` / `upsert_all` (row 76) — kino
   `/features/bulk_probe`: `insert_all!` of 3 tags, `upsert_all(unique_by:
   :name)` updates instead of duplicating, duplicate bulk INSERT raises
   `RecordNotUnique` (run inside a savepoint so the aborted statement does not
   poison an enclosing transaction). No shim changes needed.
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
18. **[DONE ✅]** Job `retry_on` / `discard_on` (row 107) —
    `job_resilience_test` (retry budget exhausted re-raises; discard_on
    swallows) + kino `/features/job_resilience_probe`: the rescue-handler
    declarations are readable from the frozen classes in a worker
    (`["StandardError"]` / `["ArgumentError"]`).
19. **[DONE ✅]** Enqueue options (row 108) — `assert_enqueued_with` main-side;
    kino `/features/job_resilience_probe`: worker-side
    `set(queue: "low", wait: 2.seconds)` reflects the queue name and a future
    `scheduled_at`. Required the shim's per-Ractor Concurrent global
    executors (ScheduledTask's GLOBAL_TIMER_SET / GLOBAL_IO_EXECUTOR constants
    are unshareable — worker-side scheduled enqueues died with IsolationError).
20. **[DONE ✅]** Mailer interceptors (row 113) — `mailer_hooks_audit_test`
    main-side (interceptor mutates at delivery, observer sees the message);
    kino `/stats/mail_hooks_probe`: the boot-registered interceptor stamps
    `X-Audit-Interceptor` on worker-delivered mail (shim snapshots the mail
    gem's hook registries as frozen hook-name lists — previously workers ran
    an empty list, so main-registered hooks silently never fired).
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
27. **[DONE ✅]** Real production cache store (rows 45–47 caveat) —
    `solid_cache` was already adopted (Gemfile, migration,
    `config/cache.yml` with `database: primary`, `production.rb` →
    `:solid_cache_store`); what was missing was worker verification. Kino
    `/solid_cache_probe`: `Rails.cache.fetch` miss+hit inside a worker
    Ractor persists a `solid_cache_entries` row (entries_delta ≥ 1) and the
    hit returns the cached value — the real store, not `:null_store`.
    Required two shim fixes: connects_to pool fallback in
    `init_worker_ar_connections!`/`connection_pool` (SolidCache::Record
    carries `default_shard == :primary` from cache.yml) and the per-Ractor
    `Entry.select_sql` memo patch.

## P2 — toolkit depth

1. **[DONE ✅]** Optimistic locking (row 71) — migration adds `lock_version`
    (default 0) to Post; Rails enables locking automatically. Verified in
    main (`active_record_toolkit_test`: stale update raises
    `ActiveRecord::StaleObjectError`, winner bumps the version) and in a
    worker via kino `/features/optimistic_lock_probe` (dedicated probe row,
    winning save 0→1, stale save raises and leaves the row untouched;
    destroy of the stale copy raises too — cleaned up via a fresh copy).
2. **[DONE ✅]** Pessimistic locking (row 72) — verified in main
    (`active_record_toolkit_test`: `Post.lock.to_sql` carries `FOR UPDATE`;
    `with_lock` transaction updates the row) and in a worker via kino
    `/features/pessimistic_lock_probe` (dedicated probe row, update inside
    the held lock, cleanup, plus the same FOR UPDATE SQL check).
3. **[DONE ✅]** `normalizes` (row 74) — `User normalizes :email, with:\n    ->(v) { v.strip.downcase }`. Verified in main (`user_test`:\n    `normalize_value_for` + instance assignment) and in a worker via kino\n    `/features/normalizes_probe` (normalizer Proc inside the attribute's\n    `NormalizedValueType` is callable cross-Ractor). Required a shim fix:\n    `SerializeCastValue::ClassMethods#serialize_cast_value_compatible?` now\n    falls back to a `method_defined?(sym, false)` ancestor scan in workers,\n    because DelegateClass-built type classes carry main-Ractor Proc-body\n    delegators and Ruby 4 refuses `instance_method`/`instance_methods` on\n    them from a worker ("defined with an un-shareable Proc in a different\n    Ractor").
4. **[DONE ✅]** STI or delegated types (row 67) — smallest: `Comment::Admin`? Prefer
    a `Vehicle/Car`-style demo on a throwaway model.
5. **[DONE ✅]** HABTM / `has_one :through` (row 68) — tiny join-table model.
6. **[DONE ✅]** `default_scope` / `unscoped` (row 78) — `Category
    default_scope { order(:name) }` (ORDER-based, safe for existing
    callers). kino `/features/default_scope_probe` in a worker: two
    dedicated rows created zulu-first so name order (default scope) and
    id order (unscoped) disagree — scope applied on worker-side reads,
    removed by `unscoped`. Main-mode coverage in `category_test`.
7. **[DONE ✅]** `strict_loading` (row 79) — kino
    `/features/strict_loading_probe` in a worker: a `Post.strict_loading`
    record raises `ActiveRecord::StrictLoadingViolationError` on a lazy
    `comments` load; `includes`-preloaded associations stay readable;
    non-strict records keep lazy loading. Main-mode coverage in
    `association_toolkit_test`. (NB: `.user` was a bad probe target —
    belongs_to with a nil FK returns nil without a load attempt.)
8. **[DONE ✅]** `load_async` (row 77) — kino `/features/load_async_probe`
    in a worker: `Post.order(:id).load_async` rides the per-Ractor
    executor (Concurrent futures — same Thread-in-Ractor class as the
    async job adapter) and materializes the committed rows; `rel.loaded?`
    true after `to_a`. Main-mode coverage in `association_toolkit_test`
    (commits for real: the async executor's separate connection cannot
    see transactional-test rows).
9. **[DONE ✅]** Advanced migrations (row 83) — `CreateAuditArchives`
    migration: `create_table` + `add_foreign_key` + named
    `add_check_constraint` + an explicit `reversible` block (table COMMENT
    with direction-specific SQL). `db:rollback STEP=1` reverts clean and
    re-migrates. `audit_archive_test` (main): FK rejects a missing post
    (`InvalidForeignKey`), check constraint bites with `validate: false`,
    jsonb containment. kino `/features/audit_archive_probe` in a worker:
    same FK/jsonb/check exercise.
10. **[DONE ✅]** Postgres types (row 82) — migration adds jsonb
    `metadata` (gin index) + string-array `trace_ids` to the polymorphic
    AuditLog table. `audit_log_test` (main): jsonb round-trip + `@>`
    containment, array round-trip + `ANY()`. kino
    `/features/audit_archive_probe` in a worker: both queries run
    worker-side (plus the row-83 jsonb on AuditArchive). Ranges/uuid PK
    not exercised — single-PK kino (documented in the row note).
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
18. **[DONE ✅]** Mailer callbacks (row 116) — `after_action` in UserMailer
    stamps `X-Audit-Campaign`; asserted main-side
    (`mailer_hooks_audit_test`) and in workers (`/stats/mail_hooks_probe`).
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
