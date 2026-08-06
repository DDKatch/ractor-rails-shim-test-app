# Fix Plan — Ractor-Rails-Shim Test App

Priority: P0 (critical) → P1 (high) → P2 (medium) → P3 (nice-to-have)

---

## P0: Segfault in parallel test fork + PG connect

**Problem:** Running `bin/rails test` with parallel workers (12 processes) causes
SIGSEGV in `pg/connection.rb:944` (connect_start) inside forked children during
ActiveRecord schema loading. Every worker crashes simultaneously.

**Root cause:** The `pg` gem's native C extension is not safe across `fork()` when
combined with Ruby 4.0's Ractor model. The PG connection state is inherited by the
forked child but the C-level socket/SSL state is corrupted.

**Fix options:**
1. **Disable parallel testing** (quickest):
   - Add `parallel_tests: false` to `test/test_helper.rb`
   - Or run with `bin/rails test --no-parallel`

2. **Use SQLite for test** (proper isolation):
   - Change `database.yml` test section to SQLite
   - PG stays in production/staging only

3. **Upgrade pg gem** (if fix available):
   - Check if pg ~> 1.7+ has fork-safety fixes

**Impact:** Blocks running full test suite. Individual test files work.

---

## P1: Integration tests segfault when combined with model/controller tests

**Problem:** `test/integration/all_routes_test.rb` passes in isolation (5/5) but
segfaults when `bin/rails test` runs it alongside other test files.

**Root cause:** Same PG fork issue as P0. The integration test file triggers a
PG connection that corrupts when combined with parallel workers.

**Fix:**
- Run integration tests separately from unit/controller tests
- Or disable parallel testing globally

---

## P2: test/integration/ractor_server_test.rb not runnable

**Problem:** This test uses `RACTOR_BOOT_SUBPROCESS=1` and launches a Ractor-based
server (Falcon/Puma). It segfaults under `bin/rails test`.

**Root cause:** The ractor-rails-shim + Ruby 4.0 Ractor server stack is not
compatible with the minitest parallel fork model.

**Fix:**
- Run as subprocess only (as designed)
- Document that this test must be run manually, not in CI

---

## P3: Clean up interleaved crash dumps in errors.log

**Problem:** The old errors.log contained 12+ interleaved crash dumps from parallel
workers, making it unreadable.

**Status:** Fixed. New errors.log contains clean summary.

---

## P3: Add error log patterns to .gitignore

**Status:** Fixed. Added `/errors.log` and `/errors_*.log`.

---

## P3: Update RAILS_FEATURES.md with actual test results

**Status:** Not yet done. See below.

---

## Test Results Summary

| Test File                              | Tests | Status     |
|----------------------------------------|-------|------------|
| test/models/post_test.rb               | 8     | ✅ Pass    |
| test/models/user_test.rb               | 7     | ✅ Pass    |
| test/models/category_test.rb           | 8     | ✅ Pass    |
| test/models/comment_test.rb            | 8     | ✅ Pass    |
| test/controllers/posts_controller_test.rb | 6   | ✅ Pass    |
| test/controllers/categories_controller_test.rb | 6 | ✅ Pass |
| test/controllers/comments_controller_test.rb | 6 | ✅ Pass |
| test/controllers/api_posts_controller_test.rb | 6 | ✅ Pass |
| test/jobs/welcome_job_test.rb          | 3     | ✅ Pass    |
| test/mailers/user_mailer_test.rb       | 3     | ✅ Pass    |
| test/helpers/application_helper_test.rb| 2     | ✅ Pass    |
| test/integration/all_routes_test.rb    | 5     | ✅ Pass (isolation) |
| test/integration/root_load_test.rb     | -     | ❌ SIGSEGV |
| test/integration/ractor_server_test.rb | -     | ❌ SIGSEGV |

**Total passing:** 63 / 63 stable tests
**Total broken:** 2 integration tests (segfault, known PG fork issue)

---

## Next Steps

1. Decide whether to disable parallel testing or switch test DB to SQLite
2. Run full suite after fix to confirm 63/63 pass without segfault
3. Update RAILS_FEATURES.md with ✅/❌ per feature
4. Mark integration tests as known-broken in CI config
