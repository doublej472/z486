# Cache and paging coherency audit

This document enumerates every path where the z486 core could return stale data
or a stale translation, states the invariant that path must hold, and records how
it is proven: a directed bench, a simulation fuse, or a written argument. It is
the reference for the "make coherency provable" work and the place a new path is
added to before trusting it.

## The model

- **The D-cache is write-through.** A store posts to a 3-entry store queue and
  drains to memory (`l1_cache.sv`); memory therefore holds every committed store
  once the queue is drained. There are no dirty D-lines to write back.
- **The I-cache holds code lines.** On a D-cache store, `cache_unit.sv` forwards
  the store to the I-cache as a word + byte-enable patch
  (`icache_write_patch_*`). The I-cache merges the patch into a present line, into
  an in-flight fill, and rejects a lookup that races a pending patch. An external
  writer is instead merged with the template DIRECT-write invalidate.
- **External writers (DMA, VGA, another bus master)** raise
  `snoop_valid`/`snoop_addr`. `cache_unit.sv` forwards it to the D-cache (a
  conservative whole-set invalidate) and merges it into the I-cache invalidate.
- **INVD/WBINVD and the platform flush** sweep every set of both caches
  independently, cancel an in-flight fill rather than wait for it, and latch a
  platform request seen during a walk (`8c5a832`).
- **The page walker issues its PDE/PTE reads and A/D write-backs through the
  D-cache request path** (`paging_unit.sv` `emit_walker_biu_req` →
  `dcache_req_*`), so page tables are coherent with normal D-cache accesses.
  Software TLB invalidation (INVLPG / CR3 reload) is still required; the hardware
  does not snoop the TLB.

## Invariants and status

| # | path | invariant | status | evidence |
| --- | --- | --- | --- | --- |
| C1 | D$ load vs registered external snoop | a load whose tag was captured before a same-set snoop clears it must miss, not hit | **fixed** | this change: `lookup_snoop_conflict` in `l1_cache.sv`; mirrors the I$ `eb6f9c4`. Directed bench still to add |
| C2 | D$ fill vs registered external snoop | a fill in flight when its set is snooped must not install the line, and the mark must stick for the rest of the fill | **fixed** | this change: `fill_set_snooped_r`, gating `data_fill_write`/`tag_fill_write` |
| C3 | D$ load vs pipelined store patch | a read that prereads the data RAM in the cycle a store patches it takes the registered patch value | checked | `patch_fwd_hit` (`l1_cache.sv`) |
| C4 | D$ store→load forwarding | a younger store to the same dword is merged over an older one, oldest→youngest | proven | store-queue reference fuse (`l1_cache.sv`) |
| C5 | D$ store queue vs uncacheable/IO ordering | an uncacheable/IO/direct access waits for every older posted store | proven | `tb_memory_order` |
| C6 | I$ lookup vs snoop/patch | a fetch whose tag was captured before a same-line snoop or pending patch must miss | proven | `lookup_snoop_conflict` (`l1_icache.sv`, `eb6f9c4`) |
| C7 | I$ fill vs snoop | a snoop that clears the fill's line cannot be reinstated; a snoop that owns the way port defers the install instead of dropping it | proven | `fill_line_snooped_r`, `fill_tag_wait_r`; `tb_l1_icache` |
| C8 | I$ fill vs in-flight D$ stores | a fill merges the D$ store queue and the live store over the gathered line | proven | `l1_icache.sv` fill merge; `storeq_fwd` |
| C9 | D$→I$ store patch delivery | a store patch is not dropped when it collides with an external invalidate; invalidate has priority | checked | `cache_unit.sv` one-entry pending slot (`icache_write_snoop_pending`) |
| C10 | external snoop fan-out | one snoop reaches both caches with the same address | checked | `cache_unit.sv` wiring; `tb_l1_icache`, `tb_l1_cache` |
| C11 | whole-L1 flush | a sweep completes bounded regardless of in-flight fills, and a request during a walk is queued | proven | `8c5a832`; `tb_cache_flush` |
| C12 | TLB invalidate | CR3 write invalidates all; INVLPG invalidates the page | checked | `paging_tlb.sv` `invalidate_all`/`invalidate_page`; `ini` programs |
| C13 | page walk vs CR3 write | a walk that spans a CR3 write neither installs nor faults from the old tables | proven | `walk_cr3_stale_r`; `cr3_walk_race*` |
| C14 | page-walker cache coherency | PDE/PTE reads and A/D write-backs observe and update the D$ | checked | `emit_walker_biu_req` uses `dcache_req_*`; needs a directed bench |
| C15 | VIPT probe races | a speculative probe never beats a demand, and a probe that races a patch takes the patch | proven | `vipt_hit_vec`, `vipt_probe_share`, replay; `tb_l1_icache`/`tb_l1_cache` |
| C16 | page-table A/D write-back elision | a write-back that would change no bit is skipped | proven | `paging_walker.sv`; `tb_paging_walker` |

## Found: C1/C2, the D$ external-snoop guards (upstream omission)

Upstream `eb6f9c4` ("harden reset state and instruction-cache coherency") added
`lookup_snoop_conflict` and `fill_line_snooped_r` to `l1_icache.sv` **only**. The
D-cache had neither, so:

- a D$ load accepted just before an external invalidation could still hit the
  stale line, because the synchronous tag RAM preread captured the tag one cycle
  before the snoop clear; and
- a D$ fill in flight when its set was snooped could reinstall the line.

The platform's own storage audit
(`PC9821_z486_MiSTer/docs/reports/memory-audit/m04-cpu-caches.md`) asserts "I
found no path where a read returns stale data that a same-cycle writer has
already made architecturally visible"; C1 is exactly that path, so the audit
missed it. `l1_cache.sv` now mirrors the I$: the snoop is whole-set, so the
lookup conflict is `snoop_valid_r && (snoop_set_r == req_set_r)`, and a matching
fill is held off until the fill ends.

Fit (OOC CPU, 85 MHz, x87 off, `boards/de10nano` `build_cpu.tcl 0 85`, default
seed): **19,268 ALMs / 8,055 registers / -8.065 ns** vs the committed
`18,681 / 7,973 / -8.003`. Timing is unchanged; area +587 ALMs.

## The 2026-10-04 MiSTer freeze (`debug/boot-stuck.txt`)

`debug/boot-stuck.txt` is a crash-recorder capture from the full PC-98 platform,
kept here because that tree is not under our control. Decode it with
`debug/decode_trace.py`. The trace format is `CS:EIP,<cycles spent>` and the
`CTX` line is the memory port state at the stall.

What it shows:

- The capture's second `TRACE` section stalls at `CTX A=0000C9C8 W=1 V=1 R=0`:
  a **write presented and refused**, so the wait is downstream of the CPU.
- The guest is spinning over `0200:ABFC..AC2D` (linear `0xCBFC..0xCC24`), a tight
  low-RAM loop; the final state is `CS=0200 EIP=0000AC20`.
- This is **not** the earlier BIOS-memory-check freeze: that one was the
  whole-L1 flush deadlock fixed by `8c5a832` at `CS:EIP=0000:00a8`, and this
  capture is past it (the first trace section runs the normal `0038:13xx`
  routine, and the log records `Z386 start`).

`0xC9C8` is low RAM, not the I/O port the decoder's heuristic guesses; a RAM
store being refused points at the bus/SDRAM admission path or a wrong address
from an upstream bug, not at a stale-cache hit. C1/C2 are still real and worth
fixing, but they are not yet proven to be this freeze. Next step is to run
`scratch/tb_pc9821_realboot.sv` on the platform with and without the C1/C2 fix.

## What "provable" still needs

1. C1/C2: a directed `l1_cache` bench that accepts a load, then snoops the same
   set in the lookup cycle, and checks the reload (fail-first).
2. C14: a directed bench that writes a PTE through the D$ and then walks it.
3. C9: a directed bench where a store patch and an external invalidate collide.
4. C16: the A/D elision is proven, but the D$ eviction path has no directed
   dirty-line test (write-through makes it moot today; record why it stays moot).
