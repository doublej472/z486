# Cache and paging coherency audit

This document enumerates every path where the z486 core could return stale data
or a stale translation, states the invariant that path must hold, and records how
it is proven: a directed bench, a simulation fuse, or a written argument. It is
the reference for the "make coherency provable" work and the place a new path is
added to before trusting it.

## The model

- **The D-cache is write-through.** A store posts to the default 4-entry queue and
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
| C1 | D$ load vs registered external snoop | a load whose tag was captured before a same-set snoop clears it must miss, not hit | **fixed** | `tb_l1_cache`: read-during-clear and registered VIPT snoop races; demand and VIPT hits both masked |
| C2 | D$ fill vs registered external snoop | a fill in flight when its set is snooped must not install the line, and the mark must stick for the rest of the fill | **fixed** | sticky same-set mark plus deferred tag install for different-set port conflicts; narrow/wide cancellation and snoop-train tests |
| C3 | D$ load vs pipelined store patch | a read that prereads the data RAM in the cycle a store patches it takes the registered patch value | checked | `patch_fwd_hit` (`l1_cache.sv`) |
| C4 | D$ store→load forwarding | a younger store to the same dword is merged over an older one, oldest→youngest | guarded | ordered merge in `l1_cache.sv`; `store_fwd_word*` and `tb_l1_cache` |
| C5 | D$ store queue vs uncacheable/IO ordering | IO/INTA/device accesses drain older stores; direct VGA transactions remain mutually ordered but may bypass unrelated RAM stores | guarded | `tb_memory_order` checks both drain and intentional VGA bypass |
| C6 | I$ lookup vs snoop/patch | a fetch whose tag was captured before a same-line snoop or pending patch must miss | proven | `lookup_snoop_conflict` (`l1_icache.sv`, `eb6f9c4`) |
| C7 | I$ fill vs snoop | a snoop that clears the fill's line cannot be reinstated; a snoop that owns the way port defers the install instead of dropping it | proven | `fill_line_snooped_r`, `fill_tag_wait_r`; `tb_l1_icache` |
| C8 | I$ fill vs in-flight D$ stores | a fill merges the D$ store queue and the live store over the gathered line | proven | `l1_icache.sv` fill merge; `storeq_fwd` |
| C9 | D$→I$ store patch delivery | a store patch is not dropped when it collides with an external invalidate; invalidate has priority | guarded | `tb_memory_order` strands a patch behind external then queued DIRECT invalidates; `tb_l1_cache` checks idle store backpressure |
| C10 | external snoop fan-out | one snoop reaches both caches with the same address | checked | `cache_unit.sv` wiring; `tb_l1_icache`, `tb_l1_cache` |
| C11 | whole-L1 flush | a sweep completes bounded regardless of in-flight fills, and a request during a walk is queued | proven | `8c5a832`; `tb_cache_flush` |
| C12 | TLB invalidate | CR3 write invalidates all; INVLPG invalidates the page | checked | `paging_tlb.sv` `invalidate_all`/`invalidate_page`; `ini` programs |
| C13 | page walk vs CR3 write | a walk that spans a CR3 write neither installs nor faults from the old tables | proven | `walk_cr3_stale_r`; `cr3_walk_race*` |
| C14 | page-walker cache coherency | PDE/PTE reads and A/D write-backs observe and update the D$ | guarded | `pte_cache_coherence`: cached PTE update, INVLPG, new-frame read/write and old-frame preservation |
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

Historical fit before this hardening pass (OOC CPU, 85 MHz, x87 off, `boards/de10nano` `build_cpu.tcl 0 85`, default
seed): **19,268 ALMs / 8,055 registers / -8.065 ns** vs the committed
`18,681 / 7,973 / -8.003`. Timing is unchanged; area +587 ALMs.

## C1 residual: the read-during-clear collision (both caches)

Mirroring the I$ guard into the D$ (above) was **incomplete**, and this is the
part the earlier audit missed twice.

`lookup_snoop_conflict` rejects a hit only in the cycle the *registered* snoop
(`snoop_valid_r`) is active. But the tag read that feeds the lookup is
synchronous: a read **launched on the clearing edge** returns the OLD (valid)
entry, and that stale tag is consumed one cycle later, when `snoop_valid_r` has
already fallen and the conflict mask no longer applies. The result is a hit on a
line the clear just removed. Both caches had it:

- `l1_cache.sv`: the tag preread (`rd_tag_entry*_r <= tag_way*[preread_set]`) can
  run on the edge that clears the set. `tb_l1_cache.sv`'s "snoop invalidated
  line" case failed for exactly this reason. It had been recorded as a *bench*
  self-defect; it was not - it is a correct fail-first bench for an incomplete
  fix, and the "adding a delay passes" observation was the tell that the clear
  works but the collision is not carried forward.
- `l1_icache.sv`: a demand accepted (`accept_cpu`) on the edge that clears a
  tag-matched snoop captures the pre-clear entry, and the lookup then hits it.

Fix (both): carry the collision into the lookup. `rd_invalidated_r` records the
ways the clear removed on the read's own edge and the hit vectors mask them. The
D$ clear is whole-set, so all four ways are masked; the I$ clear is tag-matched
(plus a whole-set flush sweep), so `tag_clear_ways` selects per way.

Benches, verified fail-first in both directions:

- `tb_l1_cache.sv` "snoop invalidated line" - failed before, passes now.
- `tb_l1_icache.sv` "REGISTERED SNOOP RACE" - added. It drives the port directly
  so the accept lands in the snoop's registered cycle (`cache_read`'s ready wait
  would push it one cycle later, past the clear). Without the I$ masking it
  reports `exposed stale hit`; with it, the demand misses and refetches.

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

## Additional port-arbitration defects found and fixed

A D$ final fill and a snoop to **different sets** could need the same way's
single tag-RAM write port. The fill won and the snooped set retained a stale
valid line. The D$ now defers only the tag install while staying in S_FILL,
keeping requests out until the victim's new data and tag are coherent. The
snoop always clears its set; a later snoop of the deferred fill's own set or a
flush cancels that install. `tb_l1_cache` covers narrow/wide final beats, a train
of snoops to other sets, and later cancellation of the deferred fill. The old
code returned 11223344 after memory had been changed to DEADBEEF.

The VIPT path also lacked the demand path's **registered-cycle** conflict mask.
Carrying read-during-clear into the next cycle did not protect a probe resolving
in the current clear cycle. A separate registered-snoop qualifier now closes
that window, with a fail-first probe in the D$ bench.

The I$ held snoop-tag read could keep `tag_snoop_match*` asserted after the event,
re-clearing a later refill. Matches now include `snoop_valid_r`. A residency
regression fills four congruent lines, invalidates one, refills it, waits, and
requires the next read to hit with no additional memory request.

For patch delivery, external `snoop_valid` was not the whole port owner:
`bus_unit` can keep a DIRECT invalidate queued after the external level falls.
`cache_unit` now arbitrates against **icache_invalidate_valid**, the actual merged
input. Otherwise a collided D-store patch was cleared as consumed while the I$
was taking the queued invalidate. A one-entry patch slot also needs backpressure
on idle stores, not only pipelined LOOKUP stores. Both defects have fail-first
bench checks; a simulation fuse rejects an unconsumed-slot overwrite.

The flush arm also now closes the independent pipelined-write and VIPT
openings, not merely the registered idle ready flag. Previously a store could
still be accepted through LOOKUP's write opening, or a shared probe could hit
while a flush was armed. `tb_l1_cache` accepts the older store/probe, arms the
flush, requires all new openings/resolve hits to close, and then checks the
older store survives. Both caches mask read acceptance at the arm boundary.

## Evidence scope and remaining integration work

`make test-pc98-map` executes and modifies code in the PC-98 DIRECT aperture and
NO_ALLOC window-0 overlay with both fill response widths. A separate high-ROM
alias case executes above the tag reach, verifies no I-line is installed, and
models ignored ROM writes. These are CPU-interface guards, not a NEC firmware
or SoC boot test. The tag-width macro now controls the actual L1 tags as well as
the classification bound, instead of allowing a wider bound over fixed 27-bit
tags. The default remains 27 bits / 128 MiB.


1. ~~C1/C2: a directed `l1_cache` bench that accepts a load, then snoops the same
   set in the lookup cycle, and checks the reload (fail-first).~~ **Closed**: the
   bench existed and was correct; the fix it exposed was incomplete. See "C1
   residual" above and the `tb_l1_icache` REGISTERED SNOOP RACE case.
2. C14 now has `pte_cache_coherence`; C9 now has the collision/backpressure
   benches above. They are guards of the exercised path, not exhaustive proofs.
3. There is no dirty-line eviction test because these L1s are write-through;
   there are no dirty D-lines to evict. Revisit this if the cache policy changes.
4. The recorded boot-stuck capture is still a downstream admission observation,
   not proof that a CPU coherence fix resolves that workload. Real platform
   inputs and current FPGA timing remain separate validation requirements.
