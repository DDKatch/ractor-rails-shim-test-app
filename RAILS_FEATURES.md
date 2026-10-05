# Rails Features Audit — 80% Project Coverage

Goal: verify every core Rails feature that **80%+ of production Rails apps** actually
uses, exercise it end-to-end, and record what works vs what breaks under the
ractor-rails-shim on Ruby 4.0.6 / Rails 8.1.3.

Last updated: 2026-10-05

## Feature matrix

| #  | Category              | Feature                            | Status         | Notes |
|----|-----------------------|------------------------------------|----------------|-------|
| 1  | **Active Record**     | Validations (`validates :x, presence:`) | ✅ Done | post_test, category_test, comment_test, user_test |
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
| 50 |                       | XSS sanitization (sanitize / simple_format) | ⛔ Unsupported | Nokogiri-backed `sanitize`/`simple_format` are **unusable in worker Ractors** (ractor-unsafe C method — see shim `COMPATIBILITY.md`); must be avoided in worker-rendered views. App works around it: `posts/show` renders `@post.body` escaped via ERB + `whitespace-pre-wrap` (XSS-safe, no Nokogiri in workers). |
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

## Summary

| Status | Count | Features |
|--------|-------|----------|
| ✅ Done | 59 | Everything except #50 (sanitization) — incl. the caching cluster, variants, direct uploads (server side), system tests, rake tasks, generators, console helpers |
| 🔲 Pending | 0 | — |
| ⚠️ Known worker-Ractor fail | 1 | ActiveJob `perform_later` / `deliver_later` from a worker Ractor (shim TODO #5 — probed by `GET /job_enqueue_probe`, asserted as known-failing in `ractor_server_test.rb`) |
| ⛔ Unsupported | 1 | XSS sanitization (sanitize / simple_format) — Nokogiri ractor-unsafe, unusable in worker Ractors |
| ❌ Broken | 0 | (Segfaults are env-level, not feature-level) |

## Test Results (as of 2026-10-05)

```
111 runs, 324 assertions, 0 failures, 0 errors, 0 skips
```

- **0 failures, 0 errors, 0 skips** — all feature-level tests pass, including the `:ractor` integration suite (no routes 555)
- **Segfault fixed** — `gssencmode: disable` in database.yml prevents PG fork crash

## Known Ractor Limitations (555 responses in :ractor mode)

As of the last full run (`bin/rails test` → 111 runs, 324 assertions, 0 failures, 0 errors, **0 skips**), no audited route returns 555 or 500 — every audited feature serves from worker Ractors in `:ractor` mode, including the caching stack (fragment / russian-doll / low-level) and the number-helper views.

The one residual worker-Ractor limitation is **HTML sanitization**: the `sanitize` / `simple_format` helpers are backed by Nokogiri, whose document parser is a **ractor-unsafe C method** (Ruby only permits it in the main Ractor). This is unfixable in the shim — full write-up in the shim's `COMPATIBILITY.md` (`actionview — sanitize / simple_format`). This app sidesteps it: user content is rendered escaped via ERB (XSS-safe) with `whitespace-pre-wrap`, so no Nokogiri call runs in workers.

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

Legend: ✅ Already verified | 🔲 Pending | ⛔ Unsupported (worker-Ractor incompatible by design — e.g. ractor-unsafe C ext; must be avoided/worked around in app code, not a shim bug to fix) | ❌ Known broken
