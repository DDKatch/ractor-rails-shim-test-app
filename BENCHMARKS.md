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

## Headline results

12 cores, macOS, Ruby 4.0.6 **(patched — `DDKatch/ruby` `ractor-detach-call-caches` iseq
call-cache detach patch)**, Rails 8.1.3, PG 1.6.3; 2026-07-16 re-run (ractor-rails-shim 0.2.4), uniform
5-scale matrix, GC compaction ON by default (safe on the patched Ruby), `HealthShortCircuit` OFF by default so `/up` is measured fairly across all servers, `ab -c 64` × 2
runs — numbers below are measured, not estimates.

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | Peak RSS (MB) | Unique/footprint (MB) |
|--------|---------|-----------|------------------|-------------------|---------------|----------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | **5,080** | **1,286** | **797** | 204.9 | 178.9 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 5,245 | 1,381 | 918 | 186.0 | 161.0 |
| falcon async (-n1) | A (1 proc, fibers) | 5,062 | 1,229 | 885 | 230.0 | 214.1 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | **3,069** | **622** | **1,770** | 207.1 | 193.0 |
| puma clustered (-w5 -t1) | B (5 workers) | 17,182 | 3,493 | 1,410 | 857.0 | 765.2 |
| falcon forked (-n5) | B (5 workers) | 21,819 | 4,787 | 3,186 | 931.0 | 799.5 |
| **kino :ractor (-w5 -t5)** | B (5×5) | **2,465** | **614** | **1,224** | 255.7 | 195.0 |
| puma clustered (-w5 -t5) | B (5×5) | 18,734 | 3,910 | 2,567 | 914.7 | 811.1 |
| **falcon hybrid (-n5 --threads 5)** | B (5×5) | **16,738** | **3,097** | **2,600** | 871.6 | 820.4 |

‡ **kino `:threaded` is a valid single-process baseline** — the shim passes
`SERVER=thread` for this scenario (minimal install, same as Puma/Falcon), so the
reloader and Devise work and the write path is stable (see table, ~797 rps).

All scenarios serve `/up`, `GET /posts`, and `POST /posts` with **0 failures**.
kino `:ractor` throughput is lower than Puma/Falcon clustered (it shares one
frozen graph across Ractors and re-resolves methods per Ractor via the patched
Ruby's call-cache detach), but it is fully functional on the read and write
paths. `falcon async (-n1)` is the clean "fibers+async, no shim" data point
(single process, async fibers, ~214 MB unique — on par with kino's memory).

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
`kino :ractor` due to a suspected SIGBUS in the patched env-strings path under
Ruby 4.0 compaction. Re-testing (Ruby 4.0.6 patched, shim 0.2.4, `ab -c 64 -t 15`
× 3 runs) with compaction **enabled** ran clean — no SIGBUS/crash, 0 failed
requests.

**Why it's safe now:** the test app runs the **patched Ruby** (DDKatch/ruby
`ractor-detach-call-caches`), whose two VM-internals fixes — the iseq call-cache detach and the
env-string fix — are exactly what eliminate the compaction-time SIGBUS. The old
fear applied to stock Ruby 4.0 / the unpatched env-strings path; with the
patched Ruby those crashes no longer occur, so compaction is viable for
`kino :ractor`. It is now ON by default; opt OUT via `DISABLE_COMPACTION=1` if a
SIGBUS ever appears under an untested request pattern.

| Config | Compaction | p50 (ms) | p95 (ms) | p99 (ms) | rps |
|--------|------------|----------|----------|----------|-----|
| kino :ractor (-w5 -t1) | off | 95 | 129 | 138 | 640 |
| kino :ractor (-w5 -t1) | **on** | 95 | **110** | **129** | **655** |
| kino :ractor (-w5 -t5) | off | 103 | 118 | 140 | 620 |
| kino :ractor (-w5 -t5) | **on** | 106 | 121 | 145 | 605 |

Result: enabling compaction helps the single-worker-per-Ractor config (p95
129→110, p99 138→129, +2% rps) and is ~neutral at 5×5 (within run-to-run
variance — ab flagged high std-dev on these runs). Marginal overall, so the
harness keeps compaction **off by default** and exposes it via
`ENABLE_COMPACTION=1`.

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

## Patched Ruby (required for kino `:ractor`)

kino `:ractor` needs two fixes that are **not** in stock Ruby 4.0.x / kino:

1. **Class #1 — cross-ractor env-string SIGBUS** (`env_strings`
   `Opaque<RString>`): fixed in the patched kino fork
   [DDKatch/kino](https://github.com/DDKatch/kino) on the
   `ractor-per-ractor-env-cache` branch.
2. **Class #2 — frozen-iseq call-cache SIGBUS** (`vm_ci_hash` under worker GC
   mark): fixed in the patched Ruby fork
   [DDKatch/ruby](https://github.com/DDKatch/ruby) on the
   `ractor-detach-call-caches` branch — `rb_iseq_detach_call_caches` detaches an iseq's call
   caches from the global `vm->ci_table` and invalidates them when the iseq is
   shared across Ractors, so workers re-resolve methods fresh instead of
   dereferencing dangling callinfo pointers.

The `ractor-rails-shim` gem (0.2.4) additionally fixes the Ruby-level
Ractor-safety gaps: the per-Ractor `ActiveRecord::ConnectionHandler` is stored
in `Ractor.current` (not the per-thread `IsolatedExecutionState`), and
`ActiveModel::AttributeMethods#attribute_method_patterns_cache` is routed
through `Ractor.current`. **With the patched Ruby AND the shim**, kino `:ractor`
serves `/up`, `GET /posts`, and `POST /posts` with 0 transport failures and 0
server errors under load.

**Without the patched Ruby**, kino `:ractor` SIGBUSes under load even with the
shim — the call-cache detach is a VM-internals fix that cannot be done at the
Ruby level.
