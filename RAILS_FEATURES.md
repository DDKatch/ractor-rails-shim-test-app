# Rails Features Audit — 80% Project Coverage

Goal: verify every core Rails feature that **80%+ of production Rails apps** actually
uses, exercise it end-to-end, and record what works vs what breaks under the
ractor-rails-shim on Ruby 4.0.6 / Rails 8.1.3.

Last updated: 2026-10-06 (full Rails-guides sweep: rows 61–144 added, `TODO.md` created)

## Feature matrix

| #  | Category              | Feature                            | Status         | Notes |
|----|-----------------------|------------------------------------|----------------|-------|
| 1  | **Active Record**     | Validations (`validates :x, presence:`) | ✅ Done (main; ❌ in workers) | post_test, category_test, comment_test, user_test. WORKER GAP: `valid?` in a `:ractor`-mode worker silently returns true (empty `:validate` chain — see row 98); invalid records can SAVE in workers. Fix pending (TODO P1) |
| 2  |                       | Associations (`has_many` / `belongs_to`) | ✅ Done | Post has_many comments; User has_one_attached :avatar |
| 3  |                       | Callbacks (`before_save`, `after_create`) | ✅ Done | Post after_create; User after_create_commit |
| 4  |                       | Scopes (named, lambda)             | ✅ Done | Post.published, by_author; Category.popular |
| 5  |                       | Query interface (where, order, joins, includes) | ✅ Done | All controller tests use query interface |
| 6  |                       | Transactions                        | ✅ Done | PostsController create/update use transactions |
| 7  |                       | Migrations (add_column, add_index) | ✅ Done | 7 migrations created and run successfully |
| 8  | **Action Controller** | Filters (`before_action`, `after_action`) | ✅ Done | PostsController, CategoriesController |
| 9  |                       | Strong params (`require`/`permit`) | ✅ Done | All controllers use strong params |
| 10 |                       | Flash messages                      | ✅ Done | Layout renders flash_messages helper |
| 11 |                       | Session handling                    | ✅ Done | Devise integration |
| 12 |                       | Cookie handling                     | ✅ Done | Session cookies via Devise |
| 13 |                       | Rescue from errors (`rescue_from`)  | ✅ Done | ApplicationController rescue_from RecordNotFound, InvalidAuthenticityToken |
| 14 |                       | JSON API responses                  | ✅ Done | Api::PostsController returns JSON |
| 15 |                       | Streaming (`stream_from`)           | ✅ Done | ChatChannel has stream_from |
| 16  |                       | Send file / data                    | ✅ Done | `DownloadsController` — `send_data` (CSV of all posts) + `send_file` (report rendered to `tmp/`); `downloads_controller_test.rb` |
| 17 |                       | Before/after filters (ordering)     | ✅ Done | PostsController has set_post before_action |
| 18 |                       | Action filters (verify_authenticity_token) | ✅ Done | CSRF protection verified |
| 19 | **Action View**       | Partials                            | ✅ Done | _post, _form, _category, _comment partials |
| 20 |                       | Helpers (module helpers)            | ✅ Done | ApplicationHelper, PostsHelper, CategoriesHelper |
| 21 |                       | Form helpers (`form_with`, `form_for`) | ✅ Done | Posts, Categories views use form_with |
| 22 |                       | Date/time helpers                   | ✅ Done | time_ago helper in ApplicationHelper |
| 23  |                       | Number helpers                      | ✅ Done | `formatted_count` / `formatted_currency` / `formatted_percentage` in ApplicationHelper, rendered in `posts/index`; NOTE: `en.yml` was missing the `number.format` section, which made every number helper raise `TypeError` (Rails 8.1 merges `number.format` into each namespace's options) — completed the standard section |
| 24 |                       | URL helpers                         | ✅ Done | Routes generate correct paths |
| 25 | **Layouts & Views**   | Application layout                  | ✅ Done | layouts/application.html.erb |
| 26 |                       | Yield + content_for                | ✅ Done | Layout yields to views |
| 27 |                       | layouts[:mailer]                    | ✅ Done | UserMailer uses mailer layout |
| 28 | **Active Job**        | perform_later / perform_now         | ✅ Done | WelcomeJob performs_later in test |
| 29 |                       | Job queue adapters (inline/async)   | ✅ Done | test adapter runs inline |
| 30 |                       | Callbacks (before/after perform)    | ✅ Done | WelcomeJob has before_perform, after_perform |
| 31 | **Action Mailer**     | Delivering emails                   | ✅ Done | UserMailer.welcome_email.deliver_now |
| 32  |                       | Mailer previews                     | ✅ Done | `test/mailers/previews/user_mailer_preview.rb` (3 previews, fall back to unsaved records when the DB is empty); served by `/rails/mailers` in dev |
| 33  |                       | Attachments                         | ✅ Done | `UserMailer.report_email` attaches a posts CSV; asserted filename/mime/content |
| 34  |                       | Multiple recipients (CC/BCC)        | ✅ Done | Same `report_email` sets `cc:` + `bcc:` |
| 35 | **Action Cable**      | Channels                            | ✅ Done | ChatChannel subscribes to room_<id> |
| 36 |                       | WebSocket connections               | ✅ Done | ApplicationCable::Connection verified |
| 37 |                       | Broadcasting                        | ✅ Done | ChatChannel broadcasts_to |
| 38 | **Active Storage**    | File uploads (has_one_attached)     | ✅ Done | User has_one_attached :avatar (disk service) |
| 39  |                       | Variants (image processing)         | ✅ Done | `User#avatar_thumbnail` (`resize_to_limit: [100,100]`, mini_magick processor); fixture PNG in `test/fixtures/files/`; variant record asserted |
| 40  |                       | Direct uploads                      | ✅ Done (server side) | `POST /rails/active_storage/direct_uploads` mints the signed upload URL + `Blob.create_before_direct_upload!` asserted. The JS client is NOT wired (the layout ships no javascript tags) — wire it before testing real browser flows |
| 41 |                       | Blob / attachment lifecycle         | ✅ Done | User avatar attach/detach works |
| 42 | **I18n**              | Translations (t / l / localize)     | ✅ Done | config/locales/en.yml with full translations |
| 43 |                       | Pluralization                       | ✅ Done | en.messages.count defined |
| 44 |                       | Locale switching                    | ✅ Done | Locale available in I18n config |
| 45  | **Caching**           | Fragment caching                    | ✅ Done | `posts/index` (outer key: page + `Post.maximum(:updated_at)`) + `posts/show` body; test env uses `:memory_store` + `perform_caching = true` |
| 46  |                       | Russian doll caching                | ✅ Done | Inner `cache post` / `cache comment` fragments nested in the outer ones; comment fragments survive a post bust while busted outer fragments re-render (asserted via cache instrumentation events) |
| 47  |                       | Low-level caching (Rails.cache)     | ✅ Done | `Rails.cache.fetch("posts/index/total_count", expires_in: 1.minute)` in `PostsController#index` — works in worker Ractors too (see shim fixes below) |
| 48  |                       | Sweepers / cache invalidation       | ✅ Done (replacement) | Rails 8 removed `ActionController::Sweeper`; invalidation is touch-based — `Comment belongs_to :post, touch: true` bumps `post.updated_at`, part of the post cache_key and the index fragment key (asserted) |
| 49 | **Security**          | CSRF protection                     | ✅ Done | Ractor test verifies token |
| 50 |                       | XSS sanitization (sanitize / simple_format) | ⛔ Unsupported | Nokogiri-backed `sanitize`/`simple_format` are **unusable in worker Ractors** (ractor-unsafe C method — see shim `COMPATIBILITY.md`); must be avoided in worker-rendered views. App works around it: `posts/show` renders `@post.body` escaped via ERB + `whitespace-pre-wrap` (XSS-safe, no Nokogiri in workers) — see "Living without Nokogiri (#50)" below for the full pattern + advice. |
| 51 |                       | SQL injection prevention            | ✅ Done | Uses parameterized queries |
| 52 |                       | Parameter filtering (filter_parameters) | ✅ Done | Initializer configures filter |
| 53 |                       | Content Security Policy             | ✅ Done | Initializer sets CSP headers |
| 54 | **Testing**           | Minitest / integration tests        | ✅ Done | 63 tests pass (individual files) |
| 55 |                       | Fixtures / factories                | ✅ Done | fixtures.yml with posts, users, categories, comments |
| 56  | **Testing**           | System tests                        | ✅ Done | `test/system/posts_system_test.rb` (capybara, `driven_by :rack_test` — no browser needed); capybara + selenium-webdriver added to the Gemfile |
| 57  | **Other**             | Rake tasks                          | ✅ Done | `lib/tasks/posts.rake` (`posts:stats`, `posts:recount_comments`); invoked in tests via `Rake::Task[...]` |
| 58  |                       | Generators                          | ✅ Done | `Rails::Generators.invoke("helper", ...)` run into a sandboxed `tmp/generator_audit` destination in `test/generators/` |
| 59  |                       | Console helpers                     | ✅ Done | `lib/console_helpers.rb` (`app_stats`, `make_user`, `make_post`), included into `Object` from the `console` hook in `config/application.rb` |
| 60 |                       | Asset pipeline (propshaft)          | ✅ Done | Propshaft configured |

### Rows 61–144 — full Rails-guides sweep (added 2026-10-06)

Second pass over the full Rails guides (Active Record deep toolkit, remaining
controller/view helpers, Action Mailbox, Action Text, the Solid stack, Active
Support subsystems, config/security/testing/CLI). Existing rows 1–60 are
unchanged. See `TODO.md` for the check / implement / test plan behind every
🔲 row.

| #  | Category              | Feature                            | Status         | Notes |
|----|-----------------------|------------------------------------|----------------|-------|
| 61 | **Active Record**     | CRUD + finder basics (create / find / find_by / update / destroy) | ✅ Done | Every controller + the `:ractor` CRUD flow (create/show/destroy posts & comments from workers) |
| 62 |                       | Batch processing (`find_each` / `in_batches`) | 🔲 To audit | |
| 63 |                       | Aggregates (`count`/`sum`/`average`/`min`/`max`, `pluck`/`pick`/`ids`, `exists?`) | ✅ Done (partial) | count/sum exercised by tests + `posts:stats`; `pluck`/`pick`/`exists?` unexercised explicitly |
| 64 |                       | Grouping (`group` / `having` / `distinct`) | 🔲 To audit | |
| 65 |                       | `enum`                              | 🔲 To audit | |
| 66 |                       | Polymorphic associations            | ✅ Done | kino `/assoc_probe` in a worker: `AuditLog.create!(loggable: post)` persists `loggable_type: "Post"`, `loggable.class` resolves to Post, `action` column round-trips |
| 67 |                       | STI / Delegated types               | ✅ Done (STI) | kino `/assoc_probe` in a worker: `Car.create!` persists the `type` discriminator; `Vehicle.where(type: "Car")` queries through the base class. Delegated types not yet exercised |
| 68 |                       | `has_and_belongs_to_many` / `has_one :through` | ✅ Done (HABTM) | kino `/assoc_probe` in a worker: `post.tags << tag` inserts through the collection (join-row link proven by ids). `has_one :through` not yet exercised |
| 69 |                       | Nested attributes (`accepts_nested_attributes_for`) | ✅ Done | kino `/assoc_probe` in a worker: `Post.create!(comments_attributes: [...])` INSERTs the nested comment (shim: Rails' `define_non_cyclic_method` Procs → real `def` redefinitions; has_one assoc-scope where-values baked for workers) |
| 70 |                       | Counter caches                      | ✅ Done | `Comment belongs_to :post, counter_cache: true`; `posts:recount_comments` repairs. kino `/assoc_probe` now asserts `comments_count == 1` after the nested-attributes create IN A WORKER |
| 71 |                       | Optimistic locking (`lock_version`) | 🔲 To audit | |
| 72 |                       | Pessimistic locking (`with_lock`)   | 🔲 To audit | |
| 73 |                       | Dirty tracking (`changed?`, `changes`, `saved_changes`) | 🔲 To audit | |
| 74 |                       | `normalizes` (Rails 7.1)            | 🔲 To audit | |
| 75 |                       | `signed_id` / `find_signed` / `token_for` | ✅ Done (implicit) | ActiveStorage blob URLs are signed ids; direct-upload flow asserted |
| 76 |                       | `insert_all` / `upsert_all`         | 🔲 To audit | |
| 77 |                       | Async queries (`load_async`)        | 🔲 To audit | |
| 78 |                       | `default_scope` / `unscoped`        | 🔲 To audit | |
| 79 |                       | `strict_loading`                    | 🔲 To audit | |
| 80 |                       | Composite primary keys              | 🔲 To audit | |
| 81 |                       | Multiple databases (`connects_to` / `connected_to`) | 🔲 To audit (low) | kino runs single PG |
| 82 |                       | Postgres types (jsonb, arrays, ranges, uuid PK) | 🔲 To audit | |
| 83 |                       | Advanced migrations (reversible, up/down, FKs, check constraints) | 🔲 To audit | row 7 covered add_column/add_index only |
| 84 |                       | Database tasks (`db:prepare` / `migrate` / `rollback`) | ✅ Done | bin/ci Setup step |
| 85 |                       | Seeds (`db/seeds.rb`)               | ✅ Done | bin/ci Seeds step |
| 86 |                       | `dependent:` options (destroy / delete_all / nullify) | ✅ Done | Cascades asserted in the ractor test (user delete → posts → comments) |
| 87 | **Action Controller** | Request / Response objects (headers, params, `request_id`) | ✅ Done (implicit) | Devise + CSRF flows read request state in workers |
| 88 |                       | Redirects (`redirect_to`)           | ✅ Done | ractor test asserts 302 on `/posts/new` unauth |
| 89 |                       | `head` / custom status responses    | ✅ Done | kino `GET /features/head` in a worker: `head :no_content` → 204 with an empty body |
| 90 |                       | `around_action` callbacks           | ⛔ Known gap | SymbolicTransport records `:around` filters but never replays them (they must wrap the yield) — shim-level design decision, see shim `FEATURES.md` "Known limitations". Decide: shim project or documented exclusion |
| 91 |                       | Conditional GET (`fresh_when` / `stale?`, ETag / Last-Modified) | ✅ Done | kino `GET /features/conditional_get` in a worker: 200 + ETag header; replaying the ETag as If-None-Match → 304 with an empty body |
| 92 |                       | HTTP authentication (basic / digest / token) | ✅ Done (basic) | kino `GET /features/basic_auth` in a worker: no credentials → 401 "HTTP Basic: Access denied."; `Basic base64(audit:secret)` → 200. Shim: halt semantics in the callback replay (`performed?` terminator). Digest/token not yet exercised |
| 93 |                       | Signed / encrypted cookie jars (`cookies.signed` / `.encrypted` / `.permanent`) | ✅ Done | kino `GET /features/cookie_jar` in a worker: `cookies.signed` and `cookies.encrypted` both round-trip (`sig-…` / `enc-…`). `.permanent` is signed+far-expiry, not separately probed |
| 94 |                       | Health endpoint (`/up`)             | ✅ Done | kino `GET /up` in a worker: 200 + rendered health-check HTML |
| 95 |                       | `ActionController::Live` (SSE)      | 🔲 To audit (low) | threads spawn fine in Ractors; streaming writes need checking |
| 96 | **Action View**       | Collection partials (`render @collection`, spacer, locals) | ✅ Done | kino `GET /posts` in a worker: 200 with `render partial: "card", collection: @posts` markup for every post (posts/index → posts/_card) |
| 97 |                       | Custom form builders / `fields_for` / nested forms | 🔲 To audit | |
| 98 |                       | `fields_with_errors` wrappers       | ❌ Broken (worker) | kino `GET /features/form_probe` in a worker renders the form but NO `field_with_errors` wrapper. Root cause: worker-side `valid?` silently returns true — `Post.__callbacks[:validate]` is EMPTY in workers (the shim's callback replay registry captures `:save`/`:process_action` chains but not `:validate`; raw `__callbacks` reads fall back to the default when `__class_attr_config` is un-shareable). Invalid records SAVE in workers → TODO P1. `valid?` in MAIN works (unit tests) |
| 99 |                       | `date_select` / `collection_select` | ✅ Done | kino `GET /features/form_probe` in a worker: `collection_select` renders `name="post[category_id]"`; `date_select` renders the `(1i)/(2i)/(3i)` year/month/day subfields. Shim: `DateTimeSelector#sec/min/hour/day/month/year` redefined as string-eval'd defs (upstream `define_method(&block)` Procs are uncallable cross-Ractor) |
| 100 |                      | Text helpers (`truncate`, `pluralize`, `highlight`) | 🔲 To audit | |
| 101 |                      | Plain multipart file upload (`file_field` + form encoding) | ✅ Done | kino `POST /features/form_echo` (multipart) in a worker: 200; Rack's multipart parser extracts the text field + the uploaded file (`probe.txt`, 23 bytes, text/plain). Shim: `DelegateClass` `special`-method Procs (incl. `<<`) redefined as real defs |
| 102 |                      | `dom_id` / RecordIdentifier         | 🔲 To audit | |
| 103 |                      | Localized views (`index.fr.html.erb`) | 🔲 To audit | |
| 104 |                      | Turbo Frames (server-rendered)      | 🔲 To audit (low) | no JS in this app — server-side rendering only |
| 105 |                      | Turbo Streams (server-rendered responses / model broadcasts) | 🔲 To audit (low) | same |
| 106 |                      | Asset helpers (`stylesheet_link_tag` via Propshaft) | ✅ Done | layout ships `stylesheet_link_tag :app` |
| 107 | **Active Job**       | `retry_on` / `discard_on`           | 🔲 To audit | |
| 108 |                      | Enqueue options (`wait:`, `wait_until:`, `queue:`, `priority:`) | 🔲 To audit | |
| 109 |                      | Custom argument serializers         | 🔲 To audit | |
| 110 |                      | Solid Queue adapter                 | 🔲 To audit | separate dispatcher process; enqueue path is DB writes — likely compatible, verify |
| 111 |                      | Job test helpers (`assert_enqueued_with`, `perform_enqueued_jobs`) | ✅ Done | `welcome_job_test` |
| 112 |                      | `perform_now` from a worker         | ✅ Done | `mail_deliver_probe` → `deliver_now` (inline perform) in worker → 200 |
| 113 | **Action Mailer**    | Interceptors & observers            | 🔲 To audit | |
| 114 |                      | Multipart emails (HTML + plain text) | ✅ Done | `report_email` renders both parts |
| 115 |                      | Delivery methods (SMTP settings)    | 🔲 To audit | test delivery ✅ via `:test` adapter; SMTP config unverified |
| 116 |                      | Mailer callbacks (`before`/`after_action`) | 🔲 To audit | |
| 117 | **Action Mailbox**   | Routing + relay ingress             | ✅ Done | `ApplicationMailbox` routes `:all => :inbox`; `InboxMailbox` records a polymorphic `AuditLog`; migration 20261006000008 |
| 118 |                      | `InboundEmail` processing (mail parsing, `bounce`, deliver-to-mailbox) | ✅ Done | `test/mailboxes/inbox_mailbox_test.rb` — `receive_inbound_email_from_mail` routes and processes; `mail` gem (pure Ruby) is off the wall |
| 119 |                      | ActionMailbox test helpers          | ✅ Done | `receive_inbound_email_from_mail` in the mailbox spec (note: `create_inbound_email_from_mail` does NOT route — use the receive_ variant) |
| 120 | **Action Text**      | `has_rich_text` + rich text rendering | ✅ Done (write + read-back; sanitize ⛔ in workers) | `has_rich_text :content` on Post; `test/controllers/rich_text_test.rb` verifies write + sanitize + render in the MAIN ractor. kino worker probes: `update!(content:)` through the ActionText association PERSISTS in a worker (shim: has_one assoc-scope where-values baked + rich-text record build fixed) and the stored content renders back on a later worker request. KNOWN LIMITATION: the sanitize step (Nokogiri) cannot run in workers (row 50), so stored markup renders HTML-escaped instead of as rich markup — render rich HTML only in main |
| 121 |                      | Rich text embeds / direct uploads   | 🔲 To audit | embeds (`rich_text_area` + attachables) unexercised |
| 122 | **Action Cable**     | Connection identifiers / rejected connections | 🔲 To audit | connection/class-level semantics live in the main-Ractor cable server (out of :ractor scope) |
| 123 |                      | Broadcasts from model callbacks & workers | ✅ Done | kino `GET /cable_probe`: `ActionCable.server.broadcast` inside a worker Ractor persists a `solid_cable_messages` row (shim: per-Ractor cable server + SolidCable configuration). Publish = DB INSERT; client delivery is the main-Ractor poller's concern |
| 124 |                      | Cable adapters (redis / solid_cable) | ✅ Done | `solid_cable` adopted (Rails 8 default stack, no Redis dependency), all envs, primary DB — no `connects_to` (see config/cable.yml for the pool-resolution rationale) |
| 125 | **Active Storage**   | Multiple services / public service  | 🔲 To audit | |
| 126 |                      | Analyzers / `analyze_later`         | 🔲 To audit | |
| 127 |                      | Blob download / proxy streaming     | 🔲 To audit | |
| 128 |                      | Encrypted (custom) service          | 🔲 To audit (low) | |
| 129 | **Active Support**   | `CurrentAttributes`                 | ✅ Done | kino `GET /features/current` in a worker: `Current.request_id` set by a `before_action`, read back by the action (per-request state). Shim: `CurrentAttributes#key`-generated methods redefined shareable |
| 130 |                      | Notifications (`subscribe`, custom events) | ✅ Done (cache events) | caching_test subscribes to `cache.*` events; custom events unexercised |
| 131 |                      | Time zones (`config.time_zone`, `in_time_zone`) | 🔲 To audit | |
| 132 |                      | Durations / time math (`2.days.ago`, `beginning_of_day`) | 🔲 To audit | pure Ruby — likely fine |
| 133 |                      | Error reporting (`Rails.error` / ErrorReporter) | 🔲 To audit | worker exceptions → reporter path |
| 134 |                      | Tagged / broadcast logging          | 🔲 To audit | |
| 135 | **Security**         | Encrypted credentials               | ✅ Done (implicit) | read at boot in the main Ractor (Devise secret); never read in workers |
| 136 |                      | force_ssl / HSTS / security headers | 🔲 To audit | |
| 137 |                      | Permissions-Policy                  | 🔲 To audit | |
| 138 | **Configuration**    | `config.x` / `config_for` / per-env config | 🔲 To audit | |
| 139 |                      | Initializers + `to_prepare` hooks   | ✅ Done | Devise, filter_parameters, CSP initializers run at boot |
| 140 | **Testing**          | Parallel testing                    | 🔲 To audit (low) | |
| 141 | **CLI**              | `rails runner` / `dbconsole` / `destroy` / `notes` | 🔲 To audit (low) | |
| 142 |                      | Scaffold-level generators (scaffold / resource / mailer) | 🔲 To audit (low) | #58 covered the helper generator via API |
| 143 | **Assets**           | `assets:precompile`                 | 🔲 To audit (low) | |
| 144 | **Engines**          | Mount an isolated engine            | 🔲 To audit (low) | |

## Summary

| Status | Count | Features |
|--------|-------|----------|
| ✅ Done | 75 | All of rows 1–60 except #50, plus 16 already-evidenced rows from the full guides sweep (CRUD, aggregates, counter caches, signed ids, dependent:, redirects, asset helpers, job test helpers, worker perform_now, multipart mail, notifications, credentials, initializers, db tasks, seeds) |
| 🔲 To audit | 67 | Rows 62–144 marked 🔲 — see `TODO.md` for the check / implement / test plan per row |
| ⛔ Known limitations | 2 | #50 sanitize / simple_format (Nokogiri, permanent) · #90 `around_action` (SymbolicTransport doesn't replay `:around` filters — shim project or documented exclusion) |
| ❌ Broken | 0 | (Segfaults are env-level, not feature-level) |

## Test Results (as of 2026-10-05)

```
111 runs, 324 assertions, 0 failures, 0 errors, 0 skips
```

- **0 failures, 0 errors, 0 skips** — all feature-level tests pass, including the `:ractor` integration suite (no routes 555)
- **Segfault fixed** — `gssencmode: disable` in database.yml prevents PG fork crash

## Known Ractor Limitations (555 responses in :ractor mode)

As of the last full run (`bin/rails test` → 111 runs, 324 assertions, 0 failures, 0 errors, **0 skips**), no audited route returns 555 or 500 — every audited feature serves from worker Ractors in `:ractor` mode, including the caching stack (fragment / russian-doll / low-level), the number-helper views, and ActiveJob enqueue from a worker (TODO #5 probe → 200 {enqueued: true}).

The one residual worker-Ractor limitation is **HTML sanitization**: the `sanitize` / `simple_format` helpers are backed by Nokogiri, whose document parser is a **ractor-unsafe C method** (Ruby only permits it in the main Ractor). This is unfixable in the shim — full write-up in the shim's `COMPATIBILITY.md` (`actionview — sanitize / simple_format`). This app sidesteps it: user content is rendered escaped via ERB (XSS-safe) with `whitespace-pre-wrap`, so no Nokogiri call runs in workers.

Caveat on the caching claims: the `:ractor` kino runs `perform_caching = true` with **no cache store configured and no `solid_cache` gem bundled**, so the production store is `:null_store` — the kino caching probes exercise the no-op path. The caching verifications (rows 45–48) are real in the test suite (`:memory_store`); TODO.md P1 item 26 adds Solid Cache to re-verify against a real store in kino.

**What WORKS in :ractor mode:**
- `GET /posts/new` (unauth) → 302 redirect (Devise before_action replay)
- `POST /posts` (bad CSRF) → 422 (CSRF validation in worker)
- `DELETE /users/sign_out` → 422 (CSRF validation)
- All in-process test suite tests (111/111 pass)

## Shim fixes required by the newly-audited features (2026-10-05)

Exercising low-level caching + number helpers in worker Ractors surfaced three
isolation walls in the shim; all fixed in the local shim repo (the test app's
Gemfile points at `path: "../ractor-rails-shim"` during development):

1. `ActiveSupport::Cache::OPTION_ALIASES` — Rails freezes the Hash
   shallowly, its Array values stay unfrozen → every `Store#fetch`/`read`/
   `write` from a worker died with IsolationError. Registered in
   `SHAREABLE_CONSTANTS` (deep-frozen at boot).
2. `ActiveSupport::Cache::Coder` pack templates + deserializer registries —
   read during cache-entry deserialization (`Coder#load`); unfrozen Strings/
   Hashes. Registered the same way.
3. `Cache::SerializerWithFallback::MessagePackWithFallback#available?` —
   lazily memoizes a class ivar; a worker making the first probe crashed on
   the ivar WRITE. Fixed by warming the probes in main before the freeze
   (`_warm_cache_serializer_fallbacks!`, wired into the
   `AppShareabilizer` pipeline).
4. `ActiveSupport::NumberHelper::NumberConverter::DEFAULTS` (+ the delimited/
   human/human-size constants) — read on every number-helper call;
   registered in `SHAREABLE_CONSTANTS`.

Shim regression specs: `ractor-rails-shim/spec/cache_option_aliases_shareable_spec.rb`
(766 runs, 0 failures).

## Living without Nokogiri (#50 workaround)

**Yes, it is possible to run this app without ever calling Nokogiri — and
that is the recommended posture.** The gem cannot be removed from the
bundle (it is a hard transitive dependency of Rails itself:
`actionview` → `rails-html-sanitizer` → `Loofah` → `Nokogiri`, plus
`rails-dom-testing` for DOM test assertions), but it can stay **uncalled**:
an un-triggered C extension is harmless in worker Ractors.

### What the app does instead

A typical Rails view renders user content with `sanitize` (strips dangerous
tags, allows some HTML) or `simple_format` (wraps text in `<p>` tags). Both
go through `rails-html-sanitizer` → Loofah → Nokogiri. `posts/show` replaces
them with one line:

```erb
<div class="whitespace-pre-wrap text-gray-700"><%= @post.body %></div>
```

- **XSS safety** comes from ERB: `<%= %>` HTML-escapes everything, so
  `<script>alert(1)</script>` renders as inert text (`&lt;script&gt;...`).
  This is *stricter* than `sanitize`, which whitelists some HTML through —
  no HTML survives at all here.
- **Formatting** comes from the Tailwind `whitespace-pre-wrap` class: the
  browser renders `
` in the body as line breaks, which is what
  `simple_format` was doing.

Trade-off: users get no rich text (no `<b>`, no links) — everything renders
as literal text.

### Advice for this app (and any `:ractor`-mode Rails app)

1. **Never call Nokogiri-backed helpers from worker-rendered code.** The
   offenders, all Nokogiri/Loofah-backed: `sanitize`, `sanitize_css`,
   `strip_tags`, `strip_links`, and `simple_format` (it sanitizes by
   default — `simple_format(text, sanitize: false)` skips it, but then
   never pass user content through it unescaped).
2. **Never call `Nokogiri` / `Loofah` directly in worker-reachable paths**
   (parsing HTML/XML fragments, building documents). The guard is a C
   method that only the main Ractor may call — the shim's `_install_loofah_patch`
   makes Loofah's `document_klass` per-Ractor, but it cannot lift the
   C-extension restriction (no shim patch can).
3. **Prefer ERB escaping + CSS.** `<%= %>`, `whitespace-pre-wrap`, and
   friends cover the "untrusted user text" case completely and are free.
4. **For rich text, use a pure-Ruby formatter** — e.g. `kramdown` (pure
   Ruby Markdown) — and render its *output* unescaped (`<%= raw %>`) only
   if you trust the formatter's output model; kramdown escapes raw HTML in
   the input by default. Avoid `commonmarker`/`nokogiri`-based converters
   (C exts).
5. **If you truly need Nokogiri**, the options are: do it in the main
   Ractor only (`Ractor.main?` guard), or sanitize in a separate process
   (background job in thread mode / a service), or wait for upstream
   Nokogiri Ractor-safety. See the shim's `COMPATIBILITY.md` row for the
   full analysis.

Legend: ✅ Already verified | 🔲 Pending | ⛔ Unsupported (worker-Ractor incompatible by design — e.g. ractor-unsafe C ext; must be avoided/worked around in app code, not a shim bug to fix) | ❌ Known broken | ⚠️ Suspected limitation — verify before relying on it
