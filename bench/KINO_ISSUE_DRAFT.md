# Draft GitHub issue for `github.com/yaroslav/kino`

> Not posted. Review before submitting.

---

**Title:** Got a Rails 8.1 app running in kino's Ractor mode, here are the numbers

Hi @yaroslav. Thanks for kino, it's well put together. I've got a real Rails 8.1 app running in Ractor mode on stock Ruby 4.0.6 and benchmarked it, figured you'd want to see the numbers.

## What the shim is

[`ractor-rails-shim`](https://github.com/DDKatch/ractor-rails-shim) (v0.2.5) makes a standard Rails 8.1 app boot and serve under `kino -m ractor` on stock Ruby 4.0.6. No fork, no threads. It freezes the app graph shareable (`Ractor.make_shareable`), installs per-Ractor AR connection handlers, and patches the Rails APIs that mutate globals at request time. Test app: [`ractor-rails-shim-test-app`](https://github.com/DDKatch/ractor-rails-shim-test-app) (Rails 8.1.3 + Devise + PG).

## What I measured

`ab -c 64 -t 30 -k`, 5s warmup, 12-core macOS, kino 0.1.3. Full data: [`BENCHMARKS.md`](https://github.com/DDKatch/ractor-rails-shim-test-app/blob/main/BENCHMARKS.md).

| Server | /up (rps) | GET /posts (rps) | POST (rps) | Peak mem (MB) |
|--------|-----------|------------------|------------|---------------|
| falcon forked (-n5) | **22,637** | **5,296** | **3,823** | 736 |
| puma clustered (-w5 -t1) | 19,338 | 3,987 | 2,755 | 720 |
| **kino :ractor (-w5 -t1)** | **3,136** | **655** | **2,073** | **166** |

The outlier is GET /posts, the DB read path, 8× below falcon.

## Where the read gap lives

My first guess was DB pool starvation or worker shortage. Two sweeps ruled both out.
- **DB pool size.** w5t1, pool 1→5→25→100: GET /posts degrades monotonically (425→404→301→101 rps). Not pool starvation.
- **Worker count.** w5→w10→w12: `/up` (no DB) halves (3196→1239 rps). Not worker shortage.

A stackprof profile of `/up` (no DB, `app.call` in isolation) shows 86% in Ruby core/Ractor runtime, 9% GC, <2% each across Rails middleware. No single hot frame. The cost is ~429 allocations per request spread thin across the middleware stack, each more expensive under Ractor's isolated heaps and cross-Ractor GC coordination than in a forked process. kino's dispatch is already lean (one FFI crossing per request, fused take+respond, frozen env cache). The `lanes`/`batch` knobs gave nothing.

My read: the gap is a Ractor runtime overhead tax on per-request allocation and GC, a VM-level cost, not a kino or shim defect. But I only profiled from the Ruby side, on macOS. The Linux Ractor story may be different, and there may be something on the kino side a Ruby profiler can't see. If you're willing to run it on a Linux box, the test app and bench harness are linked above. And if anything else comes to mind, I'm listening.
