# ractor-rails-shim-test-app

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

## Latest benchmark — multi-process kino :ractor vs best Puma/Falcon, ractor-rails-shim 0.5.1, Ruby 4.0.7, kino 0.7.1 (2026-10-26)

YJIT **on** for all servers (Rails 8.1 production default), official
Ruby 4.0.7, Rails 8.1.3.1, `ab -c 64 -t 30 -k`, 12 cores. Ruby 4.0.7 ships
the YJIT/Ractor VM-lock fix ([ruby#22224] / [ruby#18176]), so the earlier
`BENCH_YJIT_OFF` workaround is no longer needed — kino :ractor runs at
full speed with stock Rails config.

New in this run: **multi-process kino :ractor** — `BENCH_KINO_MULTIPROC=N`
launches N independent kino processes, each `-m ractor -w1 -t1` (per-process
fiber scheduler + frozen graph + DB pool). Req/s are summed across ports;
latency is the median across ports; memory is summed across all N trees.
All kino/puma/falcon rows below are one harness invocation on kino **0.7.1**
(2026-10-26): the 9 standard scenarios plus dedicated multiproc runs, against
a clean DB (posts wiped between scenarios) — directly comparable, and bold
marks the best value. The three JRuby rows are from the 2026-10-25 JRuby
comparison (JRuby servers don't depend on the kino version). The previous
kino 0.2.1 run (2026-10-25) and the full run history live in
[`BENCHMARKS.md`](./BENCHMARKS.md).

| Server | /up (rps) | GET /posts_plain (rps) | POST /posts (rps) | Peak Mem (MB, unique) |
|--------|-----------|------------------------|-------------------|-----------------------|
| **kino :ractor multiproc (4 procs × w5-t1)** | **66,726** | **19,287** | **13,563** | 1,067 |
| falcon forked (-n5) | 22,489 | 5,962 | 4,001 | 917 |
| puma clustered (-w5 -t1) | 21,575 | 4,936 | 3,169 | 938 |
| kino :ractor multiproc (5 procs × w1-t1) | 33,232 | 8,527 | 3,165 | 1,278 |
| kino :ractor multiproc (4 procs × w1-t1) | 27,907 | 6,931 | 2,003 | 1,014 |
| kino :ractor (-w5 -t1) | 16,252 | 4,306 | 3,270 | **263** |
| puma clustered (-w5 -t5) | 20,575 | 4,148 | 2,281 | 967 |
| falcon hybrid (-n5 --threads 5) | 17,272 | 4,315 | 3,750 | 963 |
| kino :ractor (-w5 -t5) | 6,577 | 3,841 | 3,164 | 318 |
| kino :threaded (-t5) | 6,328 | 1,429 | 1,282 | 205 |
| puma single (-w0 -t5) | 5,535 | 1,554 | 1,100 | 199 |
| falcon async (-n1) | 5,559 | 1,594 | 1,097 | 238 |
| puma single (-w0 -t20), MRI | 5,431 | 1,605 | 1,023 | 198 |
| jruby + puma single (-w0 -t40) | 4,513 | 2,070 | 1,162 | 1,227 |
| jruby + puma single (-w0 -t20) | 3,596 | 1,281 | 909 | 1,246 |

Peak Mem = macOS `footprint` phys_footprint (COW-aware). Three framings,
three different winners:

- **Minimum RAM:** single-process kino :ractor (-w5 -t1) at 263 MB — the
  frozen-graph sharing still wins by ~3.5× — but it is well behind on
  `/up` (the one-process scheduler wall) and last on the Kaminari read
  path.
- **Maximum throughput:** 4 procs × 5 ractors (20 workers) leads `/up`
  (2.97× falcon), the non-Kaminari read path (3.24× falcon), and the
  write path (3.39× falcon) — at +16% memory vs forked Falcon.
- **The one remaining loss:** the Kaminari read path (`GET /posts`) is
  invariant at ~2.0-2.3k rps across every kino topology while its
  limit/offset twin scaled 8.7× — the per-request `Module.new`+`include`
  method-table mutation stalls each process's whole ractor set, so it is
  a VM cost, not a topology one.
- **JRuby check (the Reddit counter-claim):** a single JVM process with
  40 Puma threads matches or slightly beats single-process MRI on the
  scalable read path — real parallelism, no GVL — but peaks at ~1.2 GB
  unique vs 198 MB for the same single-process MRI topology, and the
  `json` 3.1.0-java Coder is not thread-safe (every session-cookie
  commit 500s under load without a synchronization workaround). The
  kino frozen-graph shape is the same "shared memory, many workers" idea
  at ~1/6 the footprint and 12-50× the per-worker throughput. Details in
  [`BENCHMARKS.md`](./BENCHMARKS.md).

Throughput scales linearly in total workers: per-ractor POST rate sits in
the same ~500-680 rps band in every kino topology (654 at 5 ractors in one
process → 678 at 20 ractors in four), while packing ractors per process
trades per-ractor `/up` headroom (~6,650 isolated vs ~3,250 shared) for
worker count. The old single-process `/posts` deficit was the shared heap
(505 → ~2.0-2.3k with processes), not an inherent Ractor cost. kino
multiproc's p50s are queueing at the ractor-per-worker boundary (64
connections ÷ per-proc rate ≈ 22-95 ms), not request cost — Rails
completes each POST in 5-10 ms. Connection ceiling: 4 procs × 5 ractors ×
pool 5 = 100 = `max_connections`; smaller pools measured faster. Full
matrices, memory tables and the run history are in
[`BENCHMARKS.md`](./BENCHMARKS.md).

Versus the kino 0.2.1 run (2026-10-25, full tables in
[`BENCHMARKS.md`](./BENCHMARKS.md)): 0.7.1 lifts the packed multiproc
topology another ~15% — 58,122 → 66,726 on `/up` (2.73× → 2.97× falcon
forked), 11,784 → 13,563 POST, 18,386 → 19,287 `/posts_plain` — while the
single-proc kino topologies and the non-kino servers re-measured within
~5%, so the bump is kino-side, not machine-side. (One puma clustered
outlier at 15,645 was re-run at 21,575 and the tables take the re-run.)

[ruby#22224]: https://bugs.ruby-lang.org/issues/22224
[ruby#18176]: https://github.com/ruby/ruby/pull/18176

## Requirements

- **Official Ruby 4.0.7** (or newer; 4.0.6 minimum) with **Ractor support**,
  and **Rails 8.1.3**. No patched Ruby is required — 4.0.6 ships the
  frozen-iseq call-cache fix (#22075) and the cross-ractor env-string fix,
  and **4.0.7 additionally ships the YJIT/Ractor VM-lock fix (#22224 /
  ruby/ruby#18176)**, which removes the YJIT-off workaround for kino
  `:ractor` — prefer 4.0.7.
- **PostgreSQL** (use the `pg` gem — `sqlite3` is **ractor-unsafe** and raises
  `Ractor::UnsafeError`)
- The official **`kino` gem (0.7.1)** — works as-is on 4.0.6+; no fork or patch
  (benchmarked on 0.2.1 through 0.7.1).
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
`ab -c 64 -t 30` against `/up` (no DB), `GET /posts` (DB + render, Kaminari),
`GET /posts_plain` (same page, limit/offset — isolates the Kaminari tax), and
authenticated `POST /posts` (Devise write), and captures per-process RSS /
footprint. It seeds the benchmark user itself.

Set `BENCH_KINO_MULTIPROC=N` to add a multi-process kino :ractor scenario
(N processes × `-m ractor -w1 -t1` on ports `PORT+1..PORT+N`; per-port Req/s
summed, latency = median across ports, memory summed across trees). Set
`BENCH_KINO_MP_WORKERS=M` to change the per-process worker count (e.g. 4
procs × w5 = 20 workers). Set `BENCH_JRUBY_THREADS=N` to add the JRuby
comparison (one JVM process, Puma `-w0 -tN`; needs the JRuby distribution,
`Gemfile.jruby` + its lockfile, and `JRUBY_HOME`/`JRUBY_BIN`).

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
| `load_root.rb` | Deliberate **load-test reproducer**. Hits a *running* server's `/` with configurable concurrency/duration to reproduce ractor-worker connection errors the in-process Minitest cannot. Run against a live server (e.g. `kino -m ractor`); usage is printed in the file. |
| `bench/repro.rb` | **Sustained write-path stress harness**. Signs in once, then hammers `POST /posts` with `ab` for `REPRO_ROUNDS` rounds (default 12), reporting rps per round. On Ruby 4.0.6 the class #2 frozen-iseq SIGBUS no longer occurs, so it runs clean (302s). Lives in `bench/` alongside the main harness. |

## License

MIT (same as the parent Rails app + `ractor-rails-shim`).
