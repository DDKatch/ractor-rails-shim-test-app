# Benchmarks: kino `:ractor` vs Puma vs Falcon

**Goal:** compare kino `:ractor` throughput/latency/memory vs Puma and Falcon.

**Harness:** `ractor-rails-shim-test-app/bench/bench.rb` — boots each server,
warms up, then runs `ab -c 64 -t 15 -k` against `/up` (no DB), `/posts` (GET,
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

12 cores, macOS, Ruby 4.0.5, Rails 8.1.3, PG 1.6.3; refreshed by the
2026-07-13 re-run on patched kino, uniform 5-scale matrix, compaction off,
`ab -c 64 -t 15` × 3 runs — numbers below are measured, not estimates.

| Server | Framing | /up (rps) | GET /posts (rps) | POST /posts (rps) | Peak RSS (MB) | Unique/footprint (MB) |
|--------|---------|-----------|------------------|-------------------|---------------|----------------------|
| **kino :threaded (-t5)** | A (1 proc, 5 thr) | **4,397** | **1,200** | **817** (STABLE) | 197 | 178 |
| puma single (-w0 -t5) | A (1 proc, 5 thr) | 4,144 | 1,267 | 824 | 179 | 162 |
| falcon async (-n1) | A (1 proc, fibers) | 5,133 | 1,269 | 846 | 245 | 202 |
| **kino :ractor (-w5 -t1)** | B (5 workers) | **2,625** | **622** | POST FAIL‡‡ | 220 | 168 |
| puma clustered (-w5 -t1) | B (5 workers) | 17,060 | 3,324 | 1,875 | 848 | 753 |
| falcon forked (-n5) | B (5 workers) | 22,050 | 5,039 | 3,241 | 974 | 786 |
| **kino :ractor (-w5 -t5)** | B (5×5) | **2,207** | **2,164** | POST FAIL‡‡ | 219 | 185 |
| puma clustered (-w5 -t5) | B (5×5) | 13,963 | 3,287 | 2,131 | 928 | 793 |
| **falcon hybrid (-n5 --threads 5)** | B (5×5) | **14,271** | **3,528** | **2,246** | 964 | 784 |

‡ **kino `:threaded` boot 500 — ROOT-CAUSED + FIXED.** kino `:threaded` (single
process, plain threads — Puma/Falcon-threaded equivalent) booted but returned
500 on every request with `NoMethodError: undefined method
'require_unload_lock!' for an instance of #<Class:…>` from `railties
finisher.rb:174`. The reloader callbacks ran on the bare
`ActiveSupport::Reloader` **class object**, and Devise then broke too. **Root
cause:** the shim's `RactorRailsShim.install` (called unconditionally from
`config/boot.rb`) keyed its install scope off `ENV["SERVER"]` (minimal install
for `puma|falcon|thin|webrick|thread`; full Ractor-oriented install otherwise).
kino sets no `SERVER` env, so it got the full install even in `:threaded` mode —
whose ractor-specific patches corrupt the reloader + Devise under plain threads.
**Fix:** the benchmark now passes `SERVER=thread` for the `kino :threaded`
scenario (minimal shim install — same as Puma/Falcon), so the reloader and
Devise work and the write path is **stable**. kino `:ractor` keeps the full
install (no `SERVER` set). kino `:threaded` is now a valid single-process
baseline, ~comparable to puma single on `/up` (4,397 rps at −t5), with a fully
working Devise write path — unlike `:ractor`, which hits the frozen-iseq class
#2 crash under sustained writes.

† **kino `:ractor` reads are stable; writes are UNSTABLE under sustained load.**
This 2026-07-13 re-run at `-w5` (patched kino, `RUBY_GC_DISABLE_COMPACTION=1`,
`ab -c 64` × 3 runs): `POST /posts` **FAILS** — HTTP 500 at `-t1` (worker
ractor crashes mid-flight) and `ECONNREFUSED` at `-w5 -t5` (worker ractor dies
and the listener refuses connections) — while reads (`/up`, `/posts` GET) stay
at 0 failures. Root cause is **NOT** the env/params sharing from the old
footnote — that was the class #1 SIGBUS (`env_strings` cross-ractor
`Opaque<RString>`), fixed by the per-ractor `thread_local!` cache in
`env_strings.rs`. The remaining crash is **class #2: the frozen-iseq SIGBUS**.
`Ractor.make_shareable(app)` freezes the Rails app's iseqs; under GC the
inline-cache `klass` pointers dangle, so a worker ractor dies with `vm_ci_hash`
SIGBUS. This is fundamental to Ruby 4.0's ractor model and cannot be patched
per-method. A single `POST /posts` still works (302, row persisted); only
*sustained concurrent* writes crash. **falcon async (-n1)** remains the clean
"fibers+async, no shim" data point (single process, async fibers, ~202 MB
unique — on par with kino's memory but stable, no shim needed).

‡‡ **kino `:ractor` `POST FAIL` (both -w5 -t1 and -w5 -t5).** The two kino
`:ractor` rows show `POST /posts` as FAILED — that is the class #2 frozen-iseq
SIGBUS from footnote † (sustained concurrent writes crash the worker ractor).
Reads (`/up`, `/posts` GET) are fully stable, so the read rows above are valid.
kino `:ractor` has no working sustained-write path on Ruby 4.0.5.

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

## Patched kino

The `kino :ractor` class #1 SIGBUS (cross-ractor env-string cache) is fixed in
the patched kino fork:
[DDKatch/kino](https://github.com/DDKatch/kino) on the
`ractor-per-ractor-env-cache` branch. The class #2 frozen-iseq crash remains
unfixed (Ruby 4.0 ractor model limitation).
