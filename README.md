# ractor-rails-shim-test-app

## Benchmark — kino :ractor YJIT-off vs Puma/Falcon YJIT-on, ractor-rails-shim 0.3.1

`BENCH_KINO_YJIT_OFF=1` (kino YJIT off, puma/falcon YJIT on), Ruby 4.0.6,
Rails 8.1.3, `ab -c 64 -t 30 -k`, 12 cores.
Raw data: `bench/results/bench-20260806-120953.json`.

| Server | /up (rps) | GET /posts_plain (rps) | POST /posts (rps) | Mem (MB) |
|--------|-----------|------------------------|-------------------|----------|
| **kino :ractor (-w5 -t1)** | 12,960 | 4,328 | **3,084** | **150** |
| puma clustered (-w5 -t1) | **19,265** | 4,564 | 2,912 | 757 |
| falcon forked (-n5) | **22,489** | **5,452** | **3,673** | 772 |
| kino :ractor (-w5 -t5) | 6,949 | 3,482 | 2,096 | 168 |
| puma clustered (-w5 -t5) | 18,325 | 4,591 | 3,189 | 780 |
| falcon hybrid (-n5 --threads 5) | 16,608 | 4,490 | 2,952 | 798 |
| kino :threaded (-t5) | 6,798 | 2,019 | 1,654 | 159 |
| puma single (-w0 -t5) | 4,948 | 1,506 | 1,010 | 164 |
| falcon async (-n1) | 4,909 | 1,419 | 920 | 211 |

Mem = peak unique footprint (COW-aware). With puma/falcon at YJIT-on best,
kino :ractor (YJIT-off) is competitive on `/posts_plain` and beats puma on
POST — all at ~5× lower memory. Falcon forked (YJIT-on, 5 processes) leads
raw throughput on read/no-DB paths. The `/posts` (Kaminari) gap persists
independently of YJIT (Ruby-VM method-table barrier — upstream ruby#22224).

The reference Rails application used to validate **`ractor-rails-shim`** running
inside **`kino -m ractor`** (Ruby 4.0 Ractor-mode web server). It is a standard
Rails 8.1 app — **Devise 5**, **Propshaft**, **Kaminari**, **PostgreSQL** — that
exercises the full request path (view rendering, authenticated Devise
sign-in/sign-out, CSRF issuance + validation, and DB-backed writes) from real
worker Ractors. **No patched Ruby or kino required** — official Ruby 4.0.6
ships the frozen-iseq call-cache fix (#22075) and the cross-ractor env-string
fix, so `kino -m ractor` runs on the upstream `kino` gem (0.2.1) as-is.

This repo is the "does it actually work end-to-end" companion to the shim
[ractor-rails-shim](https://github.com/DDKatch/ractor-rails-shim) — a monkey-patch
shim that reroutes Rails' class-level instance variable accessors through
`ActiveSupport::IsolatedExecutionState`, which is Ractor-safe, letting a Rails
app run in Ractor mode without forking Rails itself. It is a proof-of-concept /
stopgap; the goal is for Rails to do this upstream, at which point the gem
becomes a no-op and can be removed. See that project's `README.md` for the
blocker map and the per-concern patch inventory, and
[`BENCHMARKS.md`](./BENCHMARKS.md) for the full kino `:ractor` vs Puma vs
Falcon benchmark analysis.

## Requirements

- **Official Ruby 4.0.6** (or newer) with **Ractor support**, and **Rails
  8.1.3**. No patched Ruby is required — 4.0.6 ships the frozen-iseq call-cache
  fix (#22075) and the cross-ractor env-string fix, so `kino -m ractor` runs
  without the DDKatch patched Ruby/kino forks.
- **PostgreSQL** (use the `pg` gem — `sqlite3` is **ractor-unsafe** and raises
  `Ractor::UnsafeError`)
- The official **`kino` gem (0.2.1)** — works as-is on 4.0.6; no fork or patch.
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

- PostgreSQL running and the **test** DB present (see `config/database.yml`) — the
  harness points `DATABASE_URL` at it,
- macOS: `export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`.

**Run:**

```sh
cd ractor-rails-shim-test-app
BENCH_DURATION=20 BENCH_CONCURRENCY=64 BENCH_RUNS=3 ruby bench/bench.rb
# or just:  ruby bench/bench.rb
```

Measured results are written as JSON to `bench/results/`.

**kino `:ractor` is fully functional on both read and write paths** under
sustained load. On official Ruby 4.0.6 with `ractor-rails-shim` 0.2.5, the whole
matrix (`/up`, `GET /posts`, `POST /posts`) serves with **0 failures** — the
frozen-iseq SIGBUS is fixed by the call-cache detach in 4.0.6 (#22075) and the
env-string fix is also present in 4.0.6. 0.2.5 additionally fixes a nil-sentinel
storage bug in the IES-routed accessors (so `Foo.x = nil`/`false` no longer falls
through to the default) and a `Ractor::IsolationError` when a worker Ractor
reloads a cold AR schema. See [`BENCHMARKS.md`](./BENCHMARKS.md) for the full
0-failure matrix and the *"No patched Ruby or kino required"* section.

### kino patch — no longer needed on Ruby 4.0.6

`kino`'s `env_strings` cache was a shared static that leaked cross-ractor
`Ractor::IsolationError` / SIGBUS under load. That fix (per-ractor
`thread_local!` caches) **ships in official Ruby 4.0.6**, so on 4.0.6 you do
**not** need to build or install a patched `kino` — the upstream `kino` gem
(0.2.1) works as-is.

For reference only (pre-4.0.6 Rubies): the patched build lived in the
[DDKatch/kino](https://github.com/DDKatch/kino) (`ractor-per-ractor-env-cache`
branch) fork. The compaction note from that era ("compaction ON by default on
the patched Ruby") does **not** apply to stock 4.0.6, where compaction stays
OFF by default.

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
| `bench/repro.rb` | **Sustained write-path stress harness**. Signs in once, then hammers `POST /posts` with `ab` for `REPRO_ROUNDS` rounds (default 12), reporting rps per round. On Ruby 4.0.6 the class #2 frozen-iseq SIGBUS no longer occurs, so it runs clean (302s). Lives in `bench/` alongside the main harness. |

## License

MIT (same as the parent Rails app + `ractor-rails-shim`).
