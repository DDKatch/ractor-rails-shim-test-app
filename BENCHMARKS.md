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

12 cores, macOS, Ruby 4.0.6 **(patched — `DDKatch/ruby` `ruby_4_0` iseq
call-cache detach patch)**, Rails 8.1.3, PG 1.6.3; 2026-07-16 re-run, uniform
5-scale matrix, compaction off (`RUBY_GC_DISABLE_COMPACTION=1`), `ab -c 64` × 2
runs — numbers below are measured, not estimates.

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | Peak RSS (MB) | Unique/footprint (MB) |
|--------|---------|-----------|------------------|-------------------|---------------|----------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | **4,894** | **1,267** | **814** | 189.1 | 164.0 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 5,070 | 1,289 | 877 | 171.5 | 147.0 |
| falcon async (-n1) | A (1 proc, fibers) | 4,733 | 1,184 | 856 | 237.9 | 202.0 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | **2,609** | **618** | **1,123** | 217.4 | 191.0 |
| puma clustered (-w5 -t1) | B (5 workers) | 17,722 | 3,332 | 1,868 | 815.4 | 739.0 |
| falcon forked (-n5) | B (5 workers) | 21,883 | 4,861 | 3,179 | 873.7 | 762.0 |
| **kino :ractor (-w5 -t5)** | B (5×5) | **1,947** | **556** | **990** | 234.5 | 215.0 |
| puma clustered (-w5 -t5) | B (5×5) | 17,673 | 3,205 | 2,111 | 823.7 | 758.0 |
| **falcon hybrid (-n5 --threads 5)** | B (5×5) | **16,160** | **3,432** | **2,260** | 876.7 | 764.0 |

‡ **kino `:threaded` is a valid single-process baseline** — the shim passes
`SERVER=thread` for this scenario (minimal install, same as Puma/Falcon), so the
reloader and Devise work and the write path is **stable** (`814` rps).

† **kino `:ractor` read AND write paths are now STABLE under sustained load.**
The 2026-07-16 re-run (patched Ruby + `ractor-rails-shim` 0.2.2,
`RUBY_GC_DISABLE_COMPACTION=1`, `ab -c 64` × 2 runs) shows `POST /posts`
returning **302** (write persisted) with **0 failures** at both `-w5 -t1` and
`-w5 -t5`, matching reads (`/up`, `/posts` GET) at 0 failures.

Previously (pre-patch) `POST /posts` crashed under sustained concurrent writes
via the **frozen-iseq SIGBUS**: `Ractor.make_shareable(app)` freezes the Rails
app's iseqs; their inline-cache `klass` pointers / callinfo keys live in the
global weak `vm->ci_table` and, under a worker Ractor's GC mark, dangle →
SIGBUS in `vm_ci_hash`. This is now fixed by detaching the call caches when an
iseq is shared across Ractors (see *Patched Ruby* below). A single `POST /posts`
always worked; only *sustained concurrent* writes crashed — now resolved.

‡‡ **kino `:ractor` `POST /posts` is GREEN (302) at both `-w5 -t1` and
`-w5 -t5`.** The earlier "POST FAIL" rows were the frozen-iseq SIGBUS, now
fixed. Reads (`/up`, `/posts` GET) were already stable; the whole matrix is now
0-failure. `falcon async (-n1)` remains the clean "fibers+async, no shim" data
point (single process, async fibers, ~202 MB unique — on par with kino's memory
but stable, no shim needed).

kino `:ractor` throughput is lower than Puma/Falcon clustered (it shares one
frozen graph across Ractors and re-resolves methods per Ractor via the detach
patch), but it is now **fully functional** on the read and write paths.

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
   `ruby_4_0` branch — `rb_iseq_detach_call_caches` detaches an iseq's call
   caches from the global `vm->ci_table` and invalidates them when the iseq is
   shared across Ractors, so workers re-resolve methods fresh instead of
   dereferencing dangling callinfo pointers.

The `ractor-rails-shim` gem (0.2.2) additionally fixes the Ruby-level
Ractor-safety gaps: the per-Ractor `ActiveRecord::ConnectionHandler` is stored
in `Ractor.current` (not the per-thread `IsolatedExecutionState`), and
`ActiveModel::AttributeMethods#attribute_method_patterns_cache` is routed
through `Ractor.current`. **With the patched Ruby AND the shim**, kino `:ractor`
serves `/up`, `GET /posts`, and `POST /posts` with 0 transport failures and 0
server errors under load.

**Without the patched Ruby**, kino `:ractor` SIGBUSes under load even with the
shim — the call-cache detach is a VM-internals fix that cannot be done at the
Ruby level.
