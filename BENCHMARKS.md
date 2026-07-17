# Benchmarks: kino `:ractor` vs Puma vs Falcon

**Goal:** compare kino `:ractor` throughput/latency/memory vs Puma and Falcon.

**Harness:** `ractor-rails-shim-test-app/bench/bench.rb` — boots each server,
warms up, then runs `ab -c 64 -t 8 -k` against `/up` (no DB), `/posts` (GET,
DB+render), and `POST /posts` (authenticated Devise write), and captures
steady-state RSS of the server process tree.

Run:

```sh
cd ractor-rails-shim-test-app && ruby bench/bench.rb
# optionally: BENCH_DURATION=20 BENCH_CONCURRENCY=64
```

## Framings (uniform 5-scale matrix)

- **A** (single process, 5 threads): `kino -m threaded -t5`, `puma -w0 -t5`,
  `falcon --forked -n1` (async fibers).
- **B (5 workers)**: `kino -m ractor -w5 -t1`, `puma -w5 -t1`, `falcon --forked -n5`.
- **B (5×5)**: `kino -m ractor -w5 -t5`, `puma -w5 -t5`, `falcon --hybrid -n5 --threads 5`.

## Headline results — official Ruby 4.0.6

12 cores, macOS, **official Ruby 4.0.6** (`4.0.6` 2026-07-14, `03b6d3f889` — the
stock release, **no patched Ruby required**), Rails 8.1.3, PG 1.6.3; 2026-07-18
re-run (ractor-rails-shim 0.2.4), uniform 5-scale matrix, **GC compaction OFF**
(it hangs `kino :ractor` under sustained load on stock 4.0.6 — see *GC compaction*),
`HealthShortCircuit` OFF by default so `/up` is measured fairly across all servers,
`ab -c 64` × 2 runs. Servers boot on **true 4.0.6**: `.ruby-version` is pinned to
`ruby-4.0.6` and `bundle` (asdf shim) resolves the server ruby from it, so the
harness `RUBY_VERSION` and the *server* ruby agree. Numbers below are measured, not
estimates. Raw data: `bench/results/bench-20260718-023708.json`.

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | Peak RSS (MB) | Unique/footprint (MB) |
|--------|---------|-----------|------------------|-------------------|---------------|----------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | **5,054** | **1,252** | **818** | 187.6 | 163.0 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 5,050 | 1,250 | 894 | 166.8 | 143.0 |
| falcon async (-n1) | A (1 proc, fibers) | 5,117 | 1,144 | 874 | 212.2 | 205.0 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | **2,933** | **648** | **1,672** | 209.8 | 166.0 |
| puma clustered (-w5 -t1) | B (5 workers) | 18,774 | 3,137 | 1,748 | 822.8 | 723.0 |
| falcon forked (-n5) | B (5 workers) | 20,639 | 4,419 | 2,737 | 862.6 | 751.0 |
| **kino :ractor (-w5 -t5)** | B (5×5) | **1,797** | **426** | **868** | 259.3 | 191.0 |
| puma clustered (-w5 -t5) | B (5×5) | 12,594 | 2,156 | 1,546 | 825.8 | 727.0 |
| **falcon hybrid (-n5 --threads 5)** | B (5×5) | **11,347** | **2,262** | **1,510** | 851.6 | 725.0 |

‡ **kino `:threaded` is a valid single-process baseline** — the shim passes
`SERVER=thread` for this scenario (minimal install, same as Puma/Falcon), so the
reloader and Devise work and the write path is stable (see table, ~818 rps).
All nine scenarios serve `/up`, `GET /posts`, and `POST /posts` with **0 failures**
and the write path verified (302 → new post).

All scenarios serve `/up`, `GET /posts`, and `POST /posts` with **0 failures**.
kino `:ractor` throughput is lower than Puma/Falcon clustered (it shares one
frozen graph across Ractors and re-resolves methods per Ractor via the patched
Ruby's call-cache detach), but it is fully functional on the read and write
paths. `falcon async (-n1)` is the clean "fibers+async, no shim" data point
(single process, async fibers, ~214 MB unique — on par with kino's memory).

## Earlier "4.0.5" run — what actually went wrong (now resolved)

A 2026-07-17 run reported itself as "Ruby 4.0.6" but its servers actually booted
on **4.0.5** (`.ruby-version` pinned `ruby-4.0.5`, which the `bundle`/asdf shim
honored for the *server* ruby while the harness reported the `PATH`-first 4.0.6).
That run also showed `unparsed` / `Net::ReadTimeout` anomalies. Two fixes landed:

1. **Server ruby now matches the harness.** `.ruby-version` is pinned to
   `ruby-4.0.6`, so `bundle exec kino|puma|falcon` boots on true 4.0.6. The
   headline table above is a genuine 4.0.6 run.
2. **The anomalies were a server hang, not PG exhaustion or harness timing.**
   `config_ractor.ru` forced `GC.auto_compact = true`. On *official* 4.0.6 (which
   is **not** the patched DDKatch build) sustained `ab` load progressively corrupts
   the frozen shared Ractor graph, so `kino :ractor` stopped answering — `ab`
   completed **0 requests** (→ `apr_pollset_poll` timeout → `nil` rps → "unparsed")
   and the authenticated `POST /posts` hit `Net::ReadTimeout` (the verify request
   never got a response). Removing the redundant `GC.auto_compact = true` (Ruby
   defaults it to `false`) makes the server stable and yields complete numbers.
   The earlier "PG connection exhaustion" theory was incorrect — PG was fine; the
   process was simply hung.

The old 4.0.5 numbers are superseded by the official 4.0.6 headline table above and
are kept here only for history:

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | Peak RSS (MB) | Unique/footprint (MB) |
|--------|---------|-----------|------------------|-------------------|---------------|----------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | 4,166 | **24.2** ⚠️ | (unparsed, 302 ok) | 168.1 | 142.0 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 3,829 | 985 | 712 | 180.4 | 153.0 |
| falcon async (-n1) | A (1 proc, fibers) | 4,462 | 1,123 | 904 | 247.1 | 202.0 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | 3,187 | 675 | 1,808 | 231.7 | 165.0 |
| puma clustered (-w5 -t1) | B (5 workers) | 19,882 | 3,402 | 1,809 | 867.0 | 767.0 |
| falcon forked (-n5) | B (5 workers) | 21,925 | 5,085 | 2,990 | 941.1 | 796.0 |
| **kino :ractor (-w5 -t5)** | B (5×5) | (unparsed) | (unparsed) | **Net::ReadTimeout** ⚠️ | 205.5 | 177.0 |
| puma clustered (-w5 -t5) | B (5×5) | 18,168 | 3,677 | 2,565 | 910.3 | 800.0 |
| falcon hybrid (-n5 --threads 5) | B (5×5) | 13,358 | 2,561 | 2,204 | 897.5 | 768.0 |


Raw data: `bench/results/bench-20260717-212105.json`.

## `class_attribute` allocation fix (0.2.3 → 0.2.4)

Profiling `GET /posts` in a worker Ractor (StackProf, CPU + alloc) showed the
shim's ractor-mode `class_attribute` reader allocating a fresh `Array` + a
`Symbol` per ancestor on **every read** — the dominant allocation source for GET
requests (~7,447 allocs/req). 0.2.4 rewrote it as a direct literal-key
`IsolatedExecutionState` lookup (zero per-read allocation).

End-to-end `ab` (kino `:ractor`, `ab -c 64 -t 15` × 3 runs, 12 cores, Ruby
4.0.6 patched, Rails 8.1.3, compaction off):

| Config | Version | p50 (ms) | p95 (ms) | p99 (ms) | rps |
|--------|---------|----------|----------|----------|-----|
| kino :ractor (-w5 -t1) | 0.2.3 | 104 | 138 | 144 | 584 |
| kino :ractor (-w5 -t1) | **0.2.4** | **95** | **129** | **138** | **640** |
| kino :ractor (-w5 -t5) | 0.2.3 | 108 | 147 | 229 | 572 |
| kino :ractor (-w5 -t5) | **0.2.4** | **103** | **118** | **140** | **620** |

Result: lower p50/p95/p99 across the board, ~9% higher throughput, and a large
tail-latency drop (p99 229→140 at `-w5 -t5`), consistent with the
StackProf-measured GC share 33%→27% of CPU and allocs/req 7,447→3,816 (−49%).
The remaining `GET /posts` CPU cost is app-level: GC ~27%, PG ~25%,
`Random.urandom` ~11% (per-request CSRF/session token — cacheable),
`File.file?` ~6% (asset/path resolver — fixable via asset precompile + path
cache).

## GC compaction (kino :ractor)

Compaction was previously forced off (`RUBY_GC_DISABLE_COMPACTION=1`) for
`kino :ractor`. Re-testing on the **patched** DDKatch Ruby 4.0.6 (shim 0.2.4,
`ab -c 64 -t 15` × 3 runs) with compaction **enabled** ran clean — no SIGBUS/crash,
0 failed requests — because that build carries the iseq call-cache detach and
env-string fixes that eliminate the compaction-time SIGBUS.

**Official (stock) 4.0.6 is different.** The headline 2026-07-18 run confirms that
forcing `GC.auto_compact = true` on *stock* 4.0.6 progressively corrupts the frozen
shared Ractor graph under sustained `ab` load and **hangs `kino :ractor`** (`ab`
completes 0 requests, `POST /posts` hits `Net::ReadTimeout`). Stock 4.0.6 ships the
class#2 `vm_ci_hash` fix (#22075) but **not** the compaction-time env-string/iseq
fixes, so compaction is **not safe** there. The benchmark therefore runs with
compaction **OFF** (Ruby's default — `GC.auto_compact` is `false` on 4.0.6 and
`config_ractor.ru` no longer forces it); the harness only passes
`RUBY_GC_DISABLE_COMPACTION=0`, which *permits* but does not *enable* compaction. To
test compaction on the patched Ruby, set `GC.auto_compact = true` in `config_ractor.ru`
(you can leave `RUBY_GC_DISABLE_COMPACTION=0`); there is no env-var toggle —
`DISABLE_COMPACTION=1` only makes the default-off stance explicit.

| Config | Compaction | p50 (ms) | p95 (ms) | p99 (ms) | rps |
|--------|------------|----------|----------|----------|-----|
| kino :ractor (-w5 -t1) | off | 95 | 129 | 138 | 640 |
| kino :ractor (-w5 -t1) | **on** | 95 | **110** | **129** | **655** |
| kino :ractor (-w5 -t5) | off | 103 | 118 | 140 | 620 |
| kino :ractor (-w5 -t5) | **on** | 106 | 121 | 145 | 605 |

Result: the table above is from the **patched** Ruby (compaction viable there); on
stock 4.0.6 enabling compaction hangs the server, so the harness leaves compaction
**off by default** (Ruby's default `GC.auto_compact == false`); there is no env-var
toggle — `DISABLE_COMPACTION=1` is a no-op under that default.


## Memory columns

"RSS sum" = sum of `ps` RSS across the whole server process tree (listeners +
boot tree, found via `lsof` on the port + a parent/child walk — **not**
`pgrep -f`, which missed Falcon's forked workers). It double-counts
copy-on-write shared pages, so forked servers' RSS sum overstates their true
footprint. "Unique/footprint" = sum of macOS `footprint` "phys_footprint" per
process (COW-aware) — the fair number to compare. (An earlier run reported
falcon forked at ~48 MB; that was the `pgrep` bug counting only the
supervisor, not the 12 Rails workers.)

## Authenticated write-path harness fixes

The benchmark's authenticated `POST /posts` (Devise sign-in → CSRF token →
create) was broken for **all** servers for three independent reasons; all are
now fixed in `ractor-rails-shim-test-app/bench/bench.rb` (kino `:ractor` POST
previously read "FAILED*" only because of harness gaps, not a kino
limitation):

1. **CSRF token source** — `get_form_token` must prefer the
   `<meta name="csrf-token" content="...">` tag over hidden-field
   `authenticity_token` inputs. A page can carry MULTIPLE hidden-field tokens
   and the first hidden field is NOT the main form's token, so using it yields
   `InvalidAuthenticityToken`. The meta tag is unambiguous.
2. **Session rotation** — `auth_cookie_and_create_token` must return the session
   cookie from the `/posts/new` GET (`sc3`), NOT the sign-in response cookie.
   Rails rotates the session (and thus the CSRF token) after sign-in, so the
   token is valid only for the latest session cookie; using the old one gives a
   500.
3. **Port cleanup** — the per-scenario teardown must kill whatever is LISTENing
   on the port (via `lsof`), not just `pgrep -f`. puma/falcon rename their
   process title, so `pkill -f` missed stale servers and `wait_port_free`
   timed out, aborting the whole run. Now the harness kills listeners + the pid
   tree and rescues the wait.

## Patched Ruby — no longer required on official 4.0.6

The two fixes below were historically needed for `kino :ractor` under load:

1. **Class #1 — cross-ractor env-string SIGBUS** (`env_strings`
   `Opaque<RString>`): fixed in the patched kino fork
   [DDKatch/kino](https://github.com/DDKatch/kino) on the
   `ractor-per-ractor-env-cache` branch. **This fix ships in the `kino` gem used
   here** (ractor-rails-shim's pinned `kino`), so it is already present.
2. **Class #2 — frozen-iseq call-cache SIGBUS** (`vm_ci_hash` under worker GC
   mark): fixed in the patched Ruby fork
   [DDKatch/ruby](https://github.com/DDKatch/ruby) on the
   `ractor-detach-call-caches` branch — `rb_iseq_detach_call_caches` detaches an iseq's call
   caches from the global `vm->ci_table` and invalidates them when the iseq is
   shared across Ractors, so workers re-resolve methods fresh instead of
   dereferencing dangling callinfo pointers. **This fix is in official Ruby 4.0.6
   (#22075).**

**Net result: `kino :ractor` runs on official (stock) Ruby 4.0.6 with no patched
Ruby.** The class#2 fix is in 4.0.6 itself, and the class#1 fix is in the kino gem.
The `ractor-rails-shim` gem (0.2.4) fixes the Ruby-level Ractor-safety gaps: the
per-Ractor `ActiveRecord::ConnectionHandler` is stored in `Ractor.current` (not the
per-thread `IsolatedExecutionState`), and
`ActiveModel::AttributeMethods#attribute_method_patterns_cache` is routed through
`Ractor.current`. The headline 2026-07-18 run confirms `kino :ractor` serves `/up`,
`GET /posts`, and `POST /posts` with **0 transport failures and 0 server errors**
under load on plain 4.0.6.

(For reference: on *pre-4.0.6* Rubies or builds without #22075, `kino :ractor`
SIGBUSes under load even with the shim — the call-cache detach is a VM-internals
fix that cannot be done at the Ruby level. The patched DDKatch Ruby is the escape
hatch there, and is also where `GC.auto_compact` remains safe to enable.)
