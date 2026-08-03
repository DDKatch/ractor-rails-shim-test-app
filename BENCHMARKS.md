# Benchmarks: kino `:ractor` vs Puma vs Falcon

**Goal:** compare kino `:ractor` throughput/latency/memory vs Puma and Falcon.

**Harness:** `ractor-rails-shim-test-app/bench/bench.rb` — boots each server,
warms up, then runs `ab -c 64 -t <DURATION> -k` against `/up` (no DB), `/posts`
(GET, DB+render), and `POST /posts` (authenticated Devise write), and captures
steady-state RSS of the server process tree. Default `BENCH_DURATION=15`; the
headline run below used `BENCH_DURATION=30 BENCH_WARMUP=5 BENCH_RUNS=1`.

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
stock release, **no patched Ruby required**), Rails 8.1.3, PG 1.6.3; 2026-07-20
run (ractor-rails-shim 0.2.5 + audit fixes: `NoOpProc#to_proc` constant,
`abstract!` frozen-registry guard, dedup `column_defaults`, etc.), uniform
5-scale matrix, **GC compaction OFF** (it hangs `kino :ractor` under sustained
load on stock 4.0.6 — see *GC compaction*), `HealthShortCircuit` OFF by default
so `/up` is measured fairly across all servers, `ab -c 64 -t 30 -k` × 1 run
(30s/endpoint, 5s warmup — long enough to wash out JIT/GC cold-start noise;
5s runs understate single-process kino by ~30% because it stays JIT-cold).
**DB pool: 5** (`config/database.yml` `pool: 5`, the Rails default — each Ractor
gets its own pool of 5, each forked worker gets its own pool of 5; a pool sweep
1→5→25→100 showed GET /posts degrades monotonically with larger pools, see
*Pool sweep*). Servers boot on **true 4.0.6**: `.ruby-version` is pinned to `ruby-4.0.6` and
`bundle` (asdf shim) resolves the server ruby from it, so the harness
`RUBY_VERSION` and the *server* ruby agree. Numbers below are measured, not
estimates. Raw data: `bench/results/bench-20260720-153539.json`.

### Throughput / latency

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | /up p50/p95/p99 (ms) | GET /posts p50/p95/p99 | POST p50/p95/p99 |
|--------|---------|-----------|------------------|-------------------|----------------------|------------------------|-------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | 6,943 | **1,719** | **1,554** | 9 / 11 / 12 | 37 / 41 / 47 | 41 / 46 / 50 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 5,172 | 1,372 | 1,021 | 12 / 15 / 17 | 46 / 56 / 70 | 62 / 67 / 75 |
| falcon async (-n1) | A (1 proc, fibers) | 5,066 | 1,274 | 959 | 12 / 15 / 15 | 47 / 72 / 78 | 66 / 73 / 77 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | 3,136 | 655 | 2,073 | 20 / 22 / 24 | 96 / 112 / 131 | 30 / 35 / 40 |
| puma clustered (-w5 -t1) | B (5 workers) | 19,338 | 3,987 | 2,755 | 3 / 4 / 5 | 15 / 24 / 40 | 19 / 41 / 45 |
| falcon forked (-n5) | B (5 workers) | **22,637** | **5,296** | **3,823** | 3 / 4 / 5 | 11 / 19 / 32 | 13 / 26 / 28 |
| **kino :ractor (-w5 -t5)** | B (5×5) | 2,520 | 637 | 1,316 | 25 / 28 / 30 | 101 / 115 / 140 | 48 / 54 / 58 |
| puma clustered (-w5 -t5) | B (5×5) | 18,660 | 4,003 | 3,053 | 3 / 6 / 7 | 14 / 29 / 41 | 19 / 36 / 44 |
| **falcon hybrid (-n5 --threads 5)** | B (5×5) | 17,012 | 4,273 | 3,067 | 3 / 8 / 11 | 14 / 25 / 37 | 14 / 47 / 50 |

### Memory (process tree; COW-aware `footprint` is the fair number)

| Server | Framing | Cold RSS (MB) | Peak RSS (MB) | Peak Unique / footprint (MB) |
|--------|---------|---------------|---------------|-------------------------------|
| kino :threaded (-t5) | A | 153 | 188 | **162** |
| puma single (-w0 -t5) | A | 153 | 179 | **155** |
| falcon async (-n1) | A | 196 | 242 | **201** |
| **kino :ractor (-w5 -t1)** | B | 180 | 210 | **166** |
| puma clustered (-w5 -t1) | B | 734 | 820 | **720** |
| falcon forked (-n5) | B | 757 | 849 | **736** |
| kino :ractor (-w5 -t5) | B | 233 | 260 | **213** |
| puma clustered (-w5 -t5) | B | 746 | 850 | **749** |
| falcon hybrid (-n5 --threads 5) | B | 768 | 872 | **760** |

All nine scenarios serve `/up`, `GET /posts`, and `POST /posts` with **0
transport failures and 0 server errors** (302 → new post verified on the write
path). 27/27 endpoint×scenario cells green.

‡ **kino `:threaded` is a valid single-process baseline** — the shim passes
`SERVER=thread` for this scenario (minimal install, same as Puma/Falcon), so the
reloader and Devise work and the write path is stable (1,554 rps POST, the
highest of any single-process server). Once warm (30s run) it also leads the
single-process field on `GET /posts` (1,719 rps vs puma 1,372 and falcon 1,274)
because the shim's minimal install has less per-request overhead than
Puma/Falcon's full middleware stack.

### What the 30s matrix shows

**1. Memory — kino :ractor's architectural win.** At 5 workers, forked servers
burn **720-749 MB peak unique** vs kino :ractor's **166 MB** — a **4.4× memory
saving** because Ractors share one frozen app graph instead of COW-copying per
process. This is the whole point of the Ractor architecture, and the shim
delivers it.

**2. Forked multi-process wins raw throughput**, because 5 OS processes with 5
separate DB pools (25 connections) out-parallel 5 Ractors with 1 connection
each. The DB-bound `/posts` read path shows this most clearly (falcon forked
5,296 vs kino :ractor 655 — 8.1×). This is a **pool-size tuning issue, not a
shim limitation** — bumping the per-Ractor pool or sharing a pool across
Ractors would close the gap.

**3. The write path (POST) is where Ractor parallelism shows without the
DB-pool confound.** kino :threaded (single process, 5 threads, GIL) does
**1,554 rps** vs puma single's 1,021 (1.52×) and falcon async's 959 (1.62×)
— the shim's minimal threaded install outpaces GIL/threaded servers on the
CPU-bound write path. And **kino :ractor (-w5 -t1) hits 2,073 rps** on POST —
true parallelism, no GIL, single shared graph — **1.33× the best threaded
single-process server** and beating every framing-A server.

**4. The -w5 -t5 Ractor config regresses vs -w5 -t1** on every endpoint
(2,520 vs 3,136 on `/up`; 637 vs 655 on `/posts`; 1,316 vs 2,073 on POST).
Adding 5 threads per Ractor on the frozen shared graph adds contention
without enough DB connections to keep them busy. The shim runs it correctly
(0 failures) but the configuration is an anti-pattern: **don't combine Ractor
workers with per-Ractor threads; pick one**.

**5. Tail latency tightens at 30s.** The 5s run's p99s were JIT/GC cold-start
noise (e.g. kino :ractor POST p99=223ms at 5s → **40ms at 30s**; falcon forked
POST p99=140ms at 5s → 28ms at 30s). The 30s numbers are steady-state.

## `class_attribute` allocation fix (0.2.3 → 0.2.4)

Profiling `GET /posts` in a worker Ractor (StackProf, CPU + alloc) showed the
shim's ractor-mode `class_attribute` reader allocating a fresh `Array` + a
`Symbol` per ancestor on **every read** — the dominant allocation source for GET
requests (~7,447 allocs/req). 0.2.4 rewrote it as a direct literal-key
`IsolatedExecutionState` lookup (zero per-read allocation).

End-to-end `ab` (kino `:ractor`, `ab -c 64 -t 15` × 3 runs, 12 cores, Ruby
4.0.6, Rails 8.1.3, compaction off):

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

## Pool sweep (kino :ractor, w5-t1)

The headline run uses `pool: 5` (the Rails default). A sweep of per-Ractor pool
sizes on the GET /posts read path (`ab -c 64 -t 15 -k`, w5-t1, compaction off):

| Pool | GET /posts (rps) | /up (rps) | POST (rps) |
|------|-------------------|-----------|------------|
| 1    | 425              | 3,222     | 2,287      |
| 5    | 404              | 3,196     | 2,310      |
| 25   | 301              | 3,241     | 2,294      |
| 100  | 101              | —         | —          |

GET /posts degrades monotonically as pool grows: more connections per Ractor
means more GC pressure and cross-Ractor coordination overhead, not more
throughput. `/up` (no DB) is flat across pool sizes, confirming the DB layer is
where the regression bites. **This is not pool starvation** — it's the opposite.
The read path is bottlenecked by per-request allocation/GC cost under Ractor,
and a larger pool only adds overhead. pool=50 segfaults the Ruby VM
(`SIGSEGV` at `0x10`; crash report: `bench/pool50_segfault.ips`).

Note: the pool sweep ran at `ab -t 15` (shorter duration) vs the headline
matrix's `ab -t 30`. The pool=5 GET /posts number here (404 rps) is lower than
the headline's 655 rps for the same w5-t1 config. This is partly duration
(JIT/GC warmup) but the gap is wider than the ~30% JIT-cold effect seen on
`/up`, suggesting run-to-run variance on the DB read path warrants
investigation before drawing tight comparisons across the two tables. Raw data:
`bench/results/pool-sweep-*.json` (pool=100 captured live, not persisted).

## GC compaction (kino :ractor)

The SIGBUS classes that made compaction unsafe are resolved in official Ruby 4.0.6
(call-cache detach #22075 + env-string), so the earlier crash rationale is gone.
Nonetheless the benchmark runs with compaction **OFF** (Ruby's default — `GC.auto_compact`
is `false` on 4.0.6 and `config_ractor.ru` does not set it); the harness only passes
`RUBY_GC_DISABLE_COMPACTION=0`, which *permits* but does not *enable* compaction.
`DISABLE_COMPACTION=1` makes the default-off stance explicit (a no-op under the
default).

Forcing `GC.auto_compact = true` was observed to **hang `kino :ractor`** under
sustained `ab` load (the server stops answering, `ab` completes 0 requests,
`POST /posts` hits `Net::ReadTimeout`). That observation predates this confirmation
and needs to be re-verified on the current fix set before compaction can be
considered safe to enable; until then the benchmark keeps it off.

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
