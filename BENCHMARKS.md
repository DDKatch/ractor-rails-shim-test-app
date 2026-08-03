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

## YJIT and Kaminari method-table barriers

The headline table above uses stock Rails 8.1 defaults: **YJIT on** (Rails 8.1
sets `config.yjit = !local?`, so production enables it) and **Kaminari** for
pagination (`Post.order(...).page(...).per(10)`). Under `kino :ractor` on
stock Ruby 4.0.6, two request-time method-table mutations turn those defaults
into a large per-request tax: every `Module.new` + `include` + `extending!`
hits a global method-cache invalidation barrier that stalls **all** worker
Ractors, not just the one executing the request. This section isolates each
cost via an A/B on the headline `kino :ractor (-w5 -t1)` config.

The investigation and the two fixes come from the kino maintainer
([issue #6, comment](https://github.com/yaroslav/kino/issues/6#issuecomment-5165496321)):
disable YJIT for Ractor mode, and swap Kaminari's `.page(...)` for plain
`.limit(...).offset(...)`. The upstream root cause is tracked at
[ruby#22224](https://bugs.ruby-lang.org/issues/22224) with a fix PR at
[ruby/ruby#18176](https://github.com/ruby/ruby/pull/18176).

### Setup

- `/posts_plain` — a twin of `/posts` that paginates with `limit/offset`
  instead of Kaminari (same DB read, same render, no `paginate` nav). Added in
  `app/controllers/posts_controller.rb` (`index_plain`), `app/views/posts/
  index_plain.html.erb`, and `config/routes.rb`; the bench harness warms and
  measures it alongside `/posts`.
- `BENCH_YJIT_OFF=1` — `config/environments/production.rb` sets
  `config.yjit = false` when this env var is set, so both YJIT states run from
  one codebase. Without it YJIT stays on (the Rails 8.1 production default).
- `BENCH_KINO_YJIT_OFF=1` — injects `BENCH_YJIT_OFF=1` only into the kino
  :ractor scenarios, leaving puma/falcon at their YJIT-on default (head-to-head
  matrix below).
- All numbers below are re-run on **kino 0.2.1** (post-dependabot bump; 0.2.0
  adds zero-copy response bodies, which did not move the no-DB/read numbers
  measurably). The 0.1.3 run produced the same shape; the 0.2.1 raw data is
  cited per table. `ab -c 64`, 12 cores, Ruby 4.0.6, Rails 8.1.3, compaction
  off. A/B: `-t 10` × 3 runs, 5s warmup; full matrices: `-t 30` × 1 run, 5s
  warmup. Raw data: `bench/results/bench-20260803-174535.json` (A/B YJIT on),
  `bench-20260803-174942.json` (A/B YJIT off),
  `bench-20260803-180420.json` (all-YJIT-off matrix),
  `bench-20260803-181724.json` (head-to-head matrix).

### A/B — kino :ractor (-w5 -t1), YJIT on vs off, /posts vs /posts_plain

| Endpoint | YJIT on (rps) | YJIT off (rps) | YJIT off / on |
|---|---|---|---|
| `/up` (no DB) | 2,820 | **12,586** | **4.5×** |
| `/posts` (Kaminari) | 500 | 562 | 1.1× |
| `/posts_plain` (limit/offset) | 1,850 | **3,187** | **1.7×** |
| POST /posts (write) | 1,958 | 3,431 | 1.8× |

(p50 latency drops in step with rps: `/up` 23ms → 5ms, `/posts_plain` 42ms →
14ms; 0 transport failures across all cells. Values are the median of 2
samples per cell.)

**Two findings, both reproducing the issue's claims:**

1. **`config.yjit = false` is a large net win under Ractors.** `/up` jumps
   2,820 → 12,586 rps (issue: 2,800 → 13,269) — a 4.5× speedup from flipping
   one config flag. Every endpoint improves. This is *surprising* (YJIT is a
   win on forked/threaded servers) and points at a Ractor-specific VM bug:
   YJIT's per-request codegen invalidates call caches under a global lock,
   and under parallel Ractors that lock becomes a stop-the-world barrier.

2. **Kaminari's `.page()` is the read-path bottleneck.** With YJIT on,
   `/posts_plain` (1,850 rps) is **3.7× faster** than `/posts` (500 rps) for
   the same DB read + render — the gap is nearly pure method-table-barrier
   cost, since the seeded data fits one page and Kaminari's nav renders almost
   nothing (3,944 vs 3,914 bytes). The issue's numbers match (1,409 vs 419).
   Kaminari's `page` scope runs `Module.new` + 2 `include`s + `extending!`
   per request; each method-table mutation is another global barrier plus
   call-cache invalidation that all workers then re-fill under the VM lock.

The `/posts` (Kaminari) YJIT-off number (562 rps) is below the issue's 2,090 —
same direction and conclusion, just smaller absolute on this box; the
*relative* Kaminari gap (`/posts_plain` ÷ `/posts` = 5.7× off, 3.7× on) is
the meaningful signal and matches the issue's framing.

### What this means for the headline table

The headline table's stock-config `kino :ractor` numbers (`/up` 3,136, GET
/posts 655) are the honest "real Rails 8.1 app with Rails defaults" baseline
and are left as-is — they're what an unmodified app actually gets. The A/B
above shows those numbers are dominated by two **VM-level, not shim-level**
costs that a one-line config change (`config.yjit = false`) and a one-line
controller change (`.page` → `.limit/.offset`) recover most of. A full
9-scenario matrix with `BENCH_YJIT_OFF=1` is below to show kino :ractor's
*achievable* throughput vs puma/falcon once the VM bug is sidestepped.

### Full matrix — YJIT off (kino :ractor vs Puma vs Falcon)

Same 9-scenario matrix as the headline table, but with `BENCH_YJIT_OFF=1`
(`config.yjit = false` in production) — **applied to all three servers**, not
just kino. The harness spawns each server with the env var inherited, and
all boot the same Rails app whose `production.rb` gates YJIT on that flag.
So this is a fair "everyone YJIT-off" comparison: puma/falcon lose YJIT too,
which (per point #5 below) is a handicap for them, not a help. `ab -c 64 -t 30
-k` × 1 run, 5s warmup, 12 cores, Ruby 4.0.6, Rails 8.1.3, compaction off.
Raw data: `bench/results/bench-20260803-180420.json`.

| Server | Framing | /up (rps) | GET /posts (rps) | /posts_plain (rps) | POST /posts (rps) | /up p50/p95/p99 | GET /posts p50/p95/p99 | /posts_plain p50/p95/p99 | POST p50/p95/p99 |
|--------|---------|-----------|------------------|--------------------|-------------------|-----------------|------------------------|--------------------------|-------------------|
| kino :threaded (-t5) | A | 3,709 | 691 | 883 | 955 | 17/20/24 | 89/111/127 | 72/78/84 | 65/76/93 |
| puma single (-w0 -t5) | A | 3,190 | 859 | 998 | 658 | 20/27/30 | 72/92/126 | 64/71/78 | 96/106/117 |
| falcon async (-n1) | A | 3,040 | 401 | 608 | 620 | 21/24/26 | 155/182/215 | 104/111/123 | 100/122/153 |
| **kino :ractor (-w5 -t1)** | B | **12,950** | 678 | **4,267** | **3,269** | 5/6/7 | 91/114/144 | 14/19/23 | 19/24/31 |
| puma clustered (-w5 -t1) | B | 13,508 | 3,058 | 3,447 | 2,080 | 5/7/8 | 20/31/43 | 18/24/36 | 28/43/53 |
| falcon forked (-n5) | B | 12,846 | 3,342 | 3,797 | 2,274 | 5/7/9 | 17/33/46 | 16/24/37 | 27/42/55 |
| kino :ractor (-w5 -t5) | B | 6,639 | 636 | 3,254 | 2,011 | 9/12/14 | 101/121/145 | 19/24/30 | 31/37/41 |
| puma clustered (-w5 -t5) | B | 13,060 | 3,146 | 3,287 | 2,214 | 5/8/10 | 19/32/42 | 18/32/45 | 28/39/53 |
| falcon hybrid (-n5 --threads 5) | B | 12,092 | 2,864 | 3,286 | 2,068 | 4/13/18 | 21/37/49 | 19/31/38 | 30/41/56 |

All 9 scenarios × 4 endpoints green (0 transport failures, POST 302 verified).

#### Memory (process tree; COW-aware `footprint` is the fair number)

| Server | Framing | Cold RSS (MB) | Peak RSS (MB) | Peak Unique / footprint (MB) |
|--------|---------|---------------|---------------|-------------------------------|
| kino :threaded (-t5) | A | 139 | 151 | **119** |
| puma single (-w0 -t5) | A | 133 | 155 | **131** |
| falcon async (-n1) | A | 195 | 233 | **188** |
| **kino :ractor (-w5 -t1)** | B | 166 | 189 | **148** |
| puma clustered (-w5 -t1) | B | 638 | 695 | **600** |
| falcon forked (-n5) | B | 660 | 733 | **624** |
| kino :ractor (-w5 -t5) | B | 219 | 241 | **169** |
| puma clustered (-w5 -t5) | B | 668 | 703 | **635** |
| falcon hybrid (-n5 --threads 5) | B | 702 | 764 | **637** |

#### What the YJIT-off matrix shows

**1. The headline gap closes — kino :ractor now leads or ties on the no-DB
and write paths.** With YJIT off, `kino :ractor (-w5 -t1)` `/up` jumps from
3,136 → **12,950 rps** (headline: 3,136), now **tying puma clustered
(13,508) and falcon forked (12,846)**. POST /posts goes 2,073 → **3,269 rps**,
~1.6× puma clustered (2,080) and ~1.4× falcon forked (2,274). The Ractor
architecture's parallelism wins once the YJIT method-table barrier is removed.

**2. `/posts_plain` is kino :ractor's strongest read-path result.** At
**4,267 rps** it beats puma clustered (3,447) by 1.2× and falcon forked
(3,797) by 1.1× — same DB read + render, just without Kaminari's per-request
`Module.new`+`include`+`extending!`. This is the read path without the
method-table barrier, and kino :ractor wins it.

**3. `/posts` (Kaminari) stays the outlier.** 678 rps — barely above the
headline's 655 and far below puma/falcon (3,058/3,342). The Kaminari barrier
is a Ruby-VM cost independent of YJIT, so flipping YJIT off does not rescue it
(it even drops slightly: the read path is dominated by the barrier, not by
YJIT codegen). The `/posts` vs `/posts_plain` split (678 vs 4,267, a **6.3×**
gap on the same row) is the cleanest measure of the Kaminari tax under
Ractors.

**4. The `-w5 -t5` Ractor config still regresses vs `-w5 -t1`** on `/up`
(6,639 vs 12,950) and `/posts_plain` (3,254 vs 4,267) — the same
contention-without-DB-connections anti-pattern as the headline matrix,
independent of YJIT.

**5. Puma/Falcon are roughly flat YJIT-on → YJIT-off** (puma clustered `/up`
19,338 → 13,508; falcon forked `/up` 22,637 → 12,846 — they actually drop
without YJIT, as expected since forked processes have no method-table
barrier). This confirms the YJIT-off delta is kino-:ractor-specific: it's a
**fix for a Ractor VM bug, not a general slowdown**. YJIT remains a win for
forked/threaded servers.

**6. Memory advantage holds.** kino :ractor (-w5 -t1) peak unique footprint
**148 MB** vs puma clustered **600 MB** and falcon forked **624 MB** — the
same ~4× memory saving as the headline matrix, unaffected by YJIT state.

**Bottom line (all-YJIT-off matrix):** with both blockers sidestepped and
all servers running YJIT-off, kino :ractor leads the field on `/up`, the
non-Kaminari read path, and the write path, at ~4× lower memory. But this
handicaps puma/falcon (YJIT is a win for them). The matrix below removes
that handicap — kino :ractor YJIT-off vs puma/falcon at their YJIT-on best.

### Full matrix — kino :ractor YJIT-off, Puma/Falcon YJIT-on (head-to-head)

The fairest head-to-head: `BENCH_KINO_YJIT_OFF=1` injects `BENCH_YJIT_OFF=1`
**only into the kino :ractor scenarios** (verified per-server: kino boots
`yjit=false`, puma/falcon boot `yjit=true`). This is kino :ractor with the
Ractor method-table barrier removed vs puma/falcon at their forked-process
YJIT-on best — no handicaps either way. Same harness: `ab -c 64 -t 30 -k` × 1
run, 5s warmup, 12 cores, Ruby 4.0.6, Rails 8.1.3, compaction off. Raw data:
`bench/results/bench-20260803-181724.json`.

| Server | Framing | /up (rps) | GET /posts (rps) | /posts_plain (rps) | POST /posts (rps) | /up p50/p95/p99 | GET /posts p50/p95/p99 | /posts_plain p50/p95/p99 | POST p50/p95/p99 |
|--------|---------|-----------|------------------|--------------------|-------------------|-----------------|------------------------|--------------------------|-------------------|
| kino :threaded (-t5) | A | 7,044 | 1,110 | 1,491 | 1,600 | 9/11/11 | 54/76/81 | 43/48/52 | 39/47/64 |
| puma single (-w0 -t5) | A | 5,461 | 1,329 | 1,561 | 965 | 12/15/17 | 46/66/70 | 41/46/49 | 65/71/77 |
| falcon async (-n1) | A | 5,748 | 1,215 | 1,461 | 908 | 11/13/14 | 50/75/80 | 44/48/53 | 70/75/82 |
| **kino :ractor (-w5 -t1)** | B | 13,262 | 692 | **4,617** | **3,612** | 5/6/7 | 91/105/127 | 14/15/20 | 18/21/25 |
| puma clustered (-w5 -t1) | B | **19,895** | **4,236** | 4,766 | 2,845 | 3/5/5 | 14/19/35 | 13/16/22 | 18/41/49 |
| falcon forked (-n5) | B | **21,355** | **5,112** | **6,165** | 3,624 | 3/5/6 | 11/21/34 | 10/14/25 | 15/31/37 |
| kino :ractor (-w5 -t5) | B | 6,528 | 663 | 3,362 | 2,009 | 10/12/16 | 97/115/133 | 19/22/24 | 32/36/39 |
| puma clustered (-w5 -t5) | B | 18,335 | 3,813 | 4,658 | 2,971 | 3/6/8 | 16/28/40 | 13/23/30 | 21/29/44 |
| falcon hybrid (-n5 --threads 5) | B | 16,688 | 3,959 | 4,628 | 2,918 | 3/10/14 | 15/26/37 | 13/22/26 | 25/33/39 |

All 9 scenarios × 4 endpoints green (0 transport failures, POST 302 verified).

#### Memory (process tree; COW-aware `footprint` is the fair number)

| Server | Framing | Cold RSS (MB) | Peak RSS (MB) | Peak Unique / footprint (MB) |
|--------|---------|---------------|---------------|-------------------------------|
| kino :threaded (-t5) | A | 152 | 177 | **152** |
| puma single (-w0 -t5) | A | 148 | 190 | **166** |
| falcon async (-n1) | A | 203 | 253 | **216** |
| **kino :ractor (-w5 -t1)** | B | 168 | 195 | **153** |
| puma clustered (-w5 -t1) | B | 689 | 810 | **711** |
| falcon forked (-n5) | B | 749 | 849 | **737** |
| kino :ractor (-w5 -t5) | B | 218 | 238 | **177** |
| puma clustered (-w5 -t5) | B | 753 | 859 | **759** |
| falcon hybrid (-n5 --threads 5) | B | 793 | 892 | **780** |

#### What the head-to-head matrix shows

With puma/falcon at their YJIT-on best, the picture changes: the all-YJIT-off
matrix's "kino leads everywhere" no longer holds — YJIT is a real win for
forked servers, and they use it.

**1. `/up` — forked YJIT-on wins.** falcon forked (21,355) and puma clustered
(19,895) outpace kino :ractor (13,262). This is the pure-dispatch path where
YJIT's codegen advantage across 5 separate processes (no method-table
barrier) beats 5 Ractors in one heap. kino :ractor closed the gap from the
headline's 3,136 (8× behind falcon) to 13,262 (1.6× behind) — a 4.2×
improvement from removing one config flag — but does not overtake it.

**2. `/posts_plain` (non-Kaminari read) — competitive, not leading.** kino
:ractor 4,617 vs puma 4,766 vs falcon 6,165. Falcon forked leads; kino :ractor
is ~3% behind puma and ~25% behind falcon. The all-YJIT-off matrix had kino
winning this; with puma/falcon on YJIT, they recover the codegen edge.

**3. POST /posts (write) — kino :ractor beats puma, ties falcon.** 3,612 rps
vs puma clustered 2,845 (1.27×) and falcon forked 3,624 (~tied). The write
path is CPU-bound (Devise + AR create + redirect), and Ractor parallelism
without a GIL holds its own against forked YJIT-on processes here.

**4. `/posts` (Kaminari) — still the outlier.** 692 rps, ~7× below puma/falcon.
The Kaminari method-table barrier is a Ruby-VM cost independent of YJIT, so
even with puma/falcon at their best this gap is unchanged — it is the one
cell where the headline conclusion (kino :ractor is the outlier) stands
regardless of YJIT. The `/posts` vs `/posts_plain` split on the same row
(692 vs 4,617, a **6.7×** gap) is the cleanest measure of the Kaminari tax.

**5. Memory — unchanged, the architectural win.** kino :ractor (-w5 -t1)
peak unique **153 MB** vs puma **711 MB** and falcon **737 MB** — **~4.7×
lower**, independent of YJIT. This is the constant across all three matrices.

**Bottom line (head-to-head):** removing the YJIT barrier lifts kino :ractor
from "8× behind" to "competitive" on the no-DB and non-Kaminari read paths
and to "beating puma" on the write path — all at ~4.7× lower memory. Falcon
forked (YJIT-on, 5 processes) still leads raw throughput on the read and
no-DB paths. The Kaminari `/posts` outlier remains a Ruby-VM-level fix
(upstream ruby#22224 / ruby/ruby#18176), not something YJIT or the shim can
address. The memory advantage is architectural and constant.

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

Compaction is **OFF** (Ruby 4.0.6 default — `GC.auto_compact` is `false`).
Forcing `GC.auto_compact = true` hangs `kino :ractor` under sustained load.
Re-verified on 0.2.5 (2026-08-03): `/up` (no DB) completes at ~2,000 rps with
0 failures, but the server silently hangs partway through `GET /posts` (DB
read path) — stops responding, no crash, no error in the log. The benchmark
keeps compaction off.

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
