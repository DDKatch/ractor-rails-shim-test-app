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
22. **[DONE ✅]** Time zones (row 131) — `config.time_zone = "Europe/Berlin"`
    verified worker-side via `/durations_probe` zone flags: `Time.zone`
    name, AR timestamp conversion, `Time.use_zone` round-trip (shim
    `9a44615`: Ractor-aware `TimeZone.[]`, `TZInfo::DataSource.get`,
    shareable `TimeZone::MAPPING`).
23. **[DONE ✅]** `Rails.error` reporting (row 133) — `/error_probe` in a
    worker: `Rails.error.handle` reports + swallows (log subscriber
    writes through the frozen worker logger); `Rails.error.record`
    reports + re-raises. Custom subscribers/context not exercised
    (qualified).
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
    Connection semantics (row 122) stay main-Ractor-scope; covered in main
    mode by `test/connections/application_cable_connection_test.rb`
    (identifier from the encrypted cookie + rejected connection).
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
11. **[DONE ✅ (rows 80 + 81)]** Composite PKs / multiple
    DBs — row 80 done: `region_stats` with PK `(region, year)`,
    `self.primary_key = [:region, :year]`; `region_stat_test` (main) +
    kino `/features/composite_pk_probe` (tuple find, PK-routed update,
    duplicate-PK `RecordNotUnique`) in a worker. Migration gotcha: `id:
    false` + a composite `primary_key:` array silently drops the PK —
    the array alone implies no id column. Row 81 DONE: a real second
    database (`*_secondary`, `db/secondary_migrate` + `migrations_paths`),
    `SecondaryRecord` with `connects_to database: { writing: :secondary,
    reading: :secondary }`, and `AuditEntry` on it. kino `/multi_db_probe`
    in a worker: secondary write + re-read, a primary read in the same
    request, and `SecondaryRecord.connected_to(role: :reading)`. Shim:
    the worker handler now puts `primary` on the default shard (it used to
    let the LAST config win), registers named databases for both roles, and
    re-establishes `connects_to` model pools from a main-captured snapshot.
12. **[DONE ✅]** Custom form builders / `fields_for` (row 97) — kino
    `/features/builder_form_probe` in a worker: `form_with builder:
    LabeledFormBuilder` renders the custom labeled-field wrapper, and a
    `fields_for` block on the comments association emits nested-attribute
    names (`post[comments_attributes][0][body]`). Main-mode coverage in
    `features_controller_test`.
13. **[DONE ✅]** `fields_with_errors` (row 98) — already covered:
    `/features/form_probe` submits a record with a deliberate :body
    error and asserts the wrapper div; kino asserts the wrapper renders
    in a worker (row-98 flip, earlier batch).
14. **[DONE ✅]** Text helpers (row 100) — kino `/features/text_helpers_probe`
    in a worker: truncate/pluralize/excerpt + highlight (plain-gsub
    path). Two Ractor notes recorded in the row: TextHelper must be
    included at boot (worker-side `include` → `Ractor::UnsafeError`),
    and `highlight` runs sanitize (Nokogiri — row 120 ⛔) by default, so
    the worker probe passes `sanitize: false`; default-sanitize
    highlight stays main-mode (`text_helpers_audit_test` — its stale
    "no Nokogiri involvement" comment was corrected).
15. **[DONE ✅]** `head` / custom statuses (row 89) — already covered:
    `/features/head` returns `head :no_content` (204, empty body);
    asserted main (`features_controller_test`) and in a worker (kino).
16. **[DONE ✅]** HTTP auth (row 92) — already covered:
    `http_basic_authenticate_with` on FeaturesController#basic_auth;
    worker kino dispatch sends the Authorization header (basic scope;
    digest/token documented as pending in the row note).
17. **[DONE ✅]** Mailer delivery methods (row 115) — kino
    `/features/config_probe` in a worker: production delivery shape
    (`:smtp`, `127.0.0.1:1025`) reads from `config.action_mailer` and
    `UserMailer.welcome_email(...).message` builds a `Mail::Message`
    worker-side (no real send — the row-113/116 delivery path already
    proves `deliver_now`). Main test env uses the `:test` adapter.
18. **[DONE ✅]** Mailer callbacks (row 116) — `after_action` in UserMailer
    stamps `X-Audit-Campaign`; asserted main-side
    (`mailer_hooks_audit_test`) and in workers (`/stats/mail_hooks_probe`).
19. **[DONE ✅]** Storage services (rows 125–127) — kino
    `/storage_probe` + follow-up proxy dispatch in a worker: a second
    PUBLIC disk service (`test_public`) resolves and routes
    upload/download worker-side; `blob.download` round-trips; the real
    `/rails/active_storage/blobs/proxy/:signed_id/:filename` route
    streams 200 + the stored bytes + content type (shim `a9059bc`:
    inline worker streaming + per-Ractor interlock + shareable
    SPECIAL_KEYS). Mirror service not exercised (optional-low).
20. **[DONE ✅]** Analyzers / `analyze_later` (row 126) — kino
    `/storage_probe` in a worker: `blob.analyze` on a text blob runs the
    analyzer chain (NullAnalyzer fallback) and `blob.analyzed?` flips.
    Image/video/audio analyzers need native libs — not exercised;
    `analyze_later` from an attachment callback is the row-120
    block-callback situation.
21. **[DONE ✅]** Durations / time math (row 132) — kino
    `/features/durations_probe` in a worker: duration-range scope
    (`Post.where(updated_at: 2.days.ago..)` matches fresh rows),
    `end_of_day`/`beginning_of_day` math, and Duration →
    `TimeWithZone`. Pure Ruby, no shim involvement.
22. **[DONE ✅]** Tagged / broadcast logging (row 134) — main-mode:
    `config.log_tags = [:request_id]` present and
    `Rails.logger.tagged` round-trips the block value
    (`features_controller_test`). Worker-side: `Rails.logger` is a
    frozen `BroadcastLogger` whose member is a plain `Logger` — the
    `TaggedLogging` extend does not survive the shim's logger freeze
    (documented in the row note as a known limitation; the probe
    reports the state, requests never call `tagged` worker-side).
23. **[DONE ✅]** force_ssl / security headers (rows 136–137) — default
    security headers (X-Frame-Options, X-Content-Type-Options,
    Referrer-Policy) asserted main + worker (kino header assertions).
    Permissions policy configured via `config.permissions_policy`; Rails
    8.1 emits it under the legacy `Feature-Policy` header name.
    `force_ssl`/HSTS stays config-level (kino is plain HTTP).
24. **[DONE ✅]** `config.x` / `config_for` (row 138) — `config.x.audit.flag`
    + `config/audit.yml` (shared + per-env); kino `/features/config_probe`
    reads both from a worker. Required shim `66d3338`:
    `Railtie::Configuration`'s `@@options` class variable is forbidden
    cross-Ractor — workers now read a frozen freeze-time snapshot
    (`RRS_FROZEN_OPTIONS`) with a per-Ractor IES overlay for writes.

## P3 — niche / low priority

51. **[DONE ✅ (rows 104 + 105)]** Turbo Frames / Streams
    server-side — row 104 done: `/features/turbo_frame_probe` renders
    hand-rolled `<turbo-frame>` wrappers (eager collection around the
    `posts/post` partial + a lazy `src` frame) in a worker; asserted in
    `ractor_server_test.rb`. Row 105 DONE: turbo-rails adopted — worker
    probes for `render turbo_stream:` (content type + `<turbo-stream>`
    markup), the `.turbo_stream.erb` handler, and a model broadcast whose
    `Turbo::Streams::ActionBroadcastJob` the `bin/jobs` dispatcher performs
    (solid_cable message row). Shim walls fixed: thread_mattr macro patch,
    turbo_stream renderer def, proc-layout registry, initialize-kind replay.
61. **[DONE ✅]** Rich text embeds / direct uploads (row 121) —
    `rich_text_area` renders in a worker; the real direct-upload endpoint
    cycle (POST direct_uploads → signed id + disk URL → disk PUT → blob
    redirect → service URL bytes) runs in workers. Embed PARSING
    (`Content#attachables`) hits the Nokogiri wall (row 50) — main-mode
    only, documented in RAILS_FEATURES row 121.
52. **[DONE ✅]** `dom_id` (row 102) — `/features/dom_id_probe` in a worker:
    `dom_id(record)`, `dom_class`, `dom_id(new)` all round-trip.
    `ActionView::RecordIdentifier` included at boot on
    FeaturesController (worker-side include would mutate the shared
    class). Main-mode coverage in `features_controller_test`.
53. **[DONE ✅]** Localized views (row 103) — `localized_probe` renders
    through a `localized_probe.en.html.erb` variant; worker asserts the
    `.en` stamp wins the lookup and the fallback variant is not picked.
54. **[DONE ✅]** `ActionController::Live` SSE (row 95) —
    `/features/live_probe` streams two events through `response.stream`
    from a worker (inline streaming per shim a9059bc); both events
    asserted in the response body.
55. **[DONE ✅]** Custom job serializers (row 109) — `GeoPoint` (Struct) +
    `GeoPointSerializer` registered via
    `ActiveJob::Serializers.add_serializers`; `/features/geo_serializer_probe`
    in a worker: registry lookup, serialize→deserialize round-trip, and
    `GeoProbeJob.perform_later(GeoPoint.new(...))` enqueue. Found + fixed a
    NEW shim wall: `ActiveJob::Serializers`' registry Set + lookup Hash
    class ivars now frozen at prepare time (shim freezer patch —
    `patches/active_job.rb`). Initializer requires the serializer files
    explicitly (initializers run before Zeitwerk autoload).
56. **[DONE ✅]** Solid Queue (row 110) — adapter set to :solid_queue in
    production semantics (the :ractor boot). kino verified END-TO-END:
    `perform_later` from a WORKER Ractor wrote the solid_queue_jobs row and
    the separate `bin/jobs` dispatcher claimed + performed it (`finished_at`
    set, the perform landed the AuditLog marker row). Found + fixed 3 shim
    walls on the way: queue_adapter fallback capture (stateless adapters
    freeze), SolidQueue::Batch.migrated? prewarm, and the execution models'
    `before_create` block callback re-registered symbolically.
57. **[DONE ✅]** Parallel testing (row 140) — `PARALLEL_WORKERS=2
    bin/rails test test/models test/controllers` → 129 runs, 0 failures.
    Processes fork (not Ractors); the earlier pg fork segfault was already
    resolved by `gssencmode: disable` in database.yml.
58. **[DONE ✅]** CLI niceties (rows 141–143) — `bin/rails runner` prints;
    `echo "SELECT 1;" | bin/rails dbconsole` psql round-trips;
    `bin/rails destroy migration` on a non-existent name no-ops without
    crashing; `bin/rails notes` runs; `generate scaffold --pretend` plans
    the full scaffold; `RAILS_ENV=production bin/rails assets:precompile`
    succeeds.
59. **[DONE ✅]** Engines (row 144) — `engines/audit_engine` path gem
    (isolate_namespace, own routes/controller/view) mounted at
    /audit_engine; worker GET renders the engine-owned view. Required the
    shim precompute step warming every engine's env_config/app memos.
60. **[DONE ✅]** Encrypted (custom) storage service (row 128) —
    app-defined `ActiveStorage::Service::EncryptedDiskService`
    (AES-256-GCM at rest); worker probe: upload → on-disk bytes differ from
    (and exclude) the plaintext → download decrypts back. Service prebuilt
    in main before the freeze (same pattern as :test_public).

## Known limitations (NOT todos)

- **#50 sanitize / simple_format / strip_tags (Nokogiri)** — permanent;
  workaround documented in `RAILS_FEATURES.md` ("Living without Nokogiri").
- **#90 `around_action`** — RESOLVED 2026-10-22, moved to the ✅ list: the
  shim now replays symbolic `:around` filters wrap-style (`SymbolicTransport#around`
  + wrap-chain `Registry#replay`; see the row-90 flip in `RAILS_FEATURES.md`).
  Lambda/Proc around filters remain fail-safe skipped (un-shareable Procs).
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
