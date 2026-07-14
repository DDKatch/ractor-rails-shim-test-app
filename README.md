# ractor-rails-shim-test-app

The reference Rails application used to validate **`ractor-rails-shim`** running
inside **`kino -m ractor`** (Ruby 4.0 Ractor-mode web server). It is a standard
Rails 8.1 app — **Devise 5**, **Propshaft**, **Kaminari**, **PostgreSQL** — that
exercises the full request path (view rendering, authenticated Devise
sign-in/sign-out, CSRF issuance + validation, and DB-backed writes) from real
worker Ractors.

This repo is the "does it actually work end-to-end" companion to the shim
[ractor-rails-shim](https://github.com/DDKatch/ractor-rails-shim). See that
project's `README.md` for the blocker map and the kino source patch, and
[`BENCHMARKS.md`](./BENCHMARKS.md) for the full kino `:ractor` vs Puma vs
Falcon benchmark analysis.

## Requirements

- **Ruby 4.0.5** (Ractor support) and **Rails 8.1.3**
- **PostgreSQL** (use the `pg` gem — `sqlite3` is **ractor-unsafe** and raises
  `Ractor::UnsafeError`)
- To serve under `kino -m ractor`: a **patched `kino` gem** (per-ractor
  env-string cache — the class #1 fix). See *"kino patch"* below. Building it
  needs **Rust ≥ 1.85** and, on macOS, `codesign`.
- **macOS fork-safety:** set `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` in the
  environment whenever you run puma *clustered* or falcon *forked* (they `fork()`
  and crash under load on macOS otherwise).

## Setup

```sh
bundle install

# Database (PostgreSQL)
rails db:create db:migrate
rails db:seed                 # dev/test: seeds test@example.com / password123

# The benchmark harness seeds its own user (signin@test.com / password) into the
# test DB, and points kino at that DB, so no manual seeding is needed for bench.
```

## Running the app (standalone)

**kino `:ractor`** (frozen shared graph, worker Ractors — memory path):

```sh
RAILS_ENV=production SECRET_KEY_BASE=dummy KINO_MODE=ractor \
  kino -m ractor -p 9293 -w5 -t1 -C kino.rb config_ractor.ru
```

**kino `:threaded`** (plain threads, live reload — dev path):

```sh
KINO_MODE=threaded kino -m threaded -p 9293 config_ractor.ru
```

**Puma** (clustered):

```sh
SERVER=puma OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  bundle exec puma config.ru -p 3000 -e production -w5
```

**Falcon** (forked):

```sh
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES bundle exec falcon config.ru -e production
```

Then exercise it:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept: text/html" http://localhost:9293/up
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept: text/html" http://localhost:9293/posts
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept: text/html" http://localhost:9293/users/sign_in
```

Sign-in works with a user that exists in the DB the server is using. For a quick
manual test, seed `test@example.com`/`password123` (via `rails db:seed`) and
sign in against the matching environment's database.

## Running the benchmarks

The harness (`bench/bench.rb`) boots **kino / puma / falcon** across a uniform
5-scale matrix (single-proc threaded, 5 workers, 5×5), warms each up, runs
`ab -c 64 -t 15` against `/up` (no DB), `GET /posts` (DB + render), and
authenticated `POST /posts` (Devise write), and captures per-process RSS /
footprint. It seeds the benchmark user itself.

**Prerequisites**

- patched `kino` installed (see *kino patch*),
- PostgreSQL running and the **test** DB present (`full_test_app_test`) — the
  harness sets `DATABASE_URL` to it,
- macOS: `export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`.

**Run:**

```sh
cd ractor-rails-shim-test-app
BENCH_DURATION=20 BENCH_CONCURRENCY=64 BENCH_RUNS=3 ruby bench/bench.rb
# or just:  ruby bench/bench.rb
```

Measured results are written as JSON to `bench/results/`.

**Known limitation (expected):** kino `:ractor` **reads are stable**, but
sustained *concurrent* `POST /posts` crashes a worker Ractor with the
**class #2 frozen-iseq SIGBUS** (fundamental to Ruby 4.0's ractor model — the
app graph is frozen, so inline-cache pointers dangle under GC). Therefore the
kino `:ractor` `POST /posts` column shows **FAIL** under load; single writes
and every read path work. This is a Ruby 4.0 limitation, not a harness gap.

### kino patch (one-time, for `:ractor` mode)

`kino`'s upstream `env_strings` cache was a shared static, which leaked
cross-ractor `Ractor::IsolationError` / SIGBUS. The fix moves those caches to
per-ractor `thread_local!`. Build the patched kino from source:

```sh
git clone https://github.com/<your-fork>/kino   # fork of yaroslav/kino @ 0.1.3
cd kino-src
asdf local rust 1.85.0            # edition2024 deps need ≥ 1.85
export LIBCLANG_PATH="$(brew --prefix llvm)/lib"   # macOS: Homebrew LLVM lib path
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
cargo build --release
# Replace the gem's compiled extension with the patched one and re-sign
# (macOS kills an ad-hoc-mismatched load with SIGKILL). The exact dylib path
# and the `codesign --force --sign -` step are documented in the published
# kino fork's build notes (see the DDKatch/kino link above).
cp target/release/libkino.dylib <kino-gem>/lib/kino/kino.bundle
codesign --force --sign - <kino-gem>/lib/kino/kino.bundle
```

See the published kino fork
[DDKatch/kino](https://github.com/DDKatch/kino) (`ractor-per-ractor-env-cache`
branch) → *"How to build/patch kino from source"* for the exact paths and the
`RUBY_GC_DISABLE_COMPACTION=1` note. The patched source lives in the published
kino fork, not in this repo.

## Automated verification

```sh
# Shim unit specs (no Rails) — clone the shim repo
# (https://github.com/DDKatch/ractor-rails-shim) and run from its directory:
bundle exec rake spec

# Full Rails suite:
bin/rails test

# Ractor worker integration (boots the frozen :ractor graph in a subprocess,
# dispatches routes into REAL worker Ractors, asserts 200 / 302 + content):
bin/rails test test/integration/ractor_server_test.rb
```

## Root / helper files

This app intentionally keeps a few **standalone helper scripts** at the repo
root (and in `bench/`) for manual reproduction *outside* the test suite. They
are not loaded by Rails and are not required to run the app or benchmarks.

| File | Purpose |
|------|---------|
| `kino.rb` | kino server configuration (worker/thread counts). Passed to kino via `-C kino.rb` from `config_ractor.ru`. Not a Rails file. |
| `verify_blockers.rb` | Boots the app in `:ractor` mode and checks key endpoints (`/up` → 200, `Post.count`, Devise routes) as a quick smoke test that the shim works outside the test framework.
| `load_root.rb` | Deliberate **load-test reproducer**. Hits a *running* server's `/` with configurable concurrency/duration to reproduce racor-worker connection errors the in-process Minitest cannot. Run against a live server (e.g. `kino -m ractor`); usage is printed in the file. |
| `bench/repro.rb` | Deliberate **sustained-crash reproducer**. Signs in once, then hammers `POST /posts` with `ab` until a worker Bus Error appears, isolating the class #2 frozen-iseq crash. Lives in `bench/` alongside the main harness. |

## License

MIT (same as the parent Rails app + `ractor-rails-shim`).
