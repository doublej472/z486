# Platform integration

`z486` is a drop-in core: everything a platform must know about the top-level
interface beyond the bus, interrupt and debug ports. The memory-map template is
[memmap-template.md](memmap-template.md); this page covers the remaining ports,
parameters and behaviours a platform sees.

## Required top-level inputs

Two inputs and one request port have **no default** and must be connected by every instantiation:

| Input | Meaning | Tie when unused |
| --- | --- | --- |
| `win0_unmapped` | Window-0 overlay verdict (0x80000-0x9FFFF target is not RAM); only effective with `WIN0_ENABLE` | `1'b0` |
| `ram_cache_top` | The platform's cacheable-RAM top (guest RAM's end); only effective with `RAM_BOUND_ENABLE` | `32'hffff_ffff` |
| `cache_flush` | Native whole-L1 flush request (held level, one walk per release) | `1'b0` |

`ram_cache_top` is the runtime half of the no-allocate bound. The template's
`NO_ALLOC_BOUND` is a flat compile-time scalar (Quartus Lite 17 rejects
unpacked-array parameters, and a compile-time bound folds); a platform whose
cacheable RAM size is a runtime choice cannot ride it. With
`RAM_BOUND_ENABLE = 1` the effective bound is `min(ram_cache_top,
NO_ALLOC_BOUND)`, so the parameter's own L1-tag-reach check still governs and the
runtime value can only tighten it. With `RAM_BOUND_ENABLE = 0` (the default)
`ram_cache_top` is unused and behaviour is identical to the parameter-only form.

## Bus lock (`lock`)

`lock` is the 486 LOCK# output (active high). While it is high, no other bus
master may take the memory bus. It covers:

- a LOCK-prefixed read-modify-write and XCHG with a memory operand, from the
  locked read until the instruction has ended and its stores have left the
  CPU (the store queue is empty and the bus accepted the write);
- the TSS busy-bit set of a task switch or LTR and the clear of the
  outgoing task's busy bit, each a locked read-modify-write of the
  descriptor's high dword;
- a descriptor accessed-bit update (only when A was clear: a segment load
  whose descriptor already has A set writes nothing);
- the page walker's A/D update, from its locked re-read of the PDE/PTE until
  the write has left the CPU (only when A or D actually changes);
- both cycles of an interrupt-acknowledge pair.

Fault and interrupt delivery is never locked, even right after a locked
instruction, and two back-to-back locked instructions keep `lock` high across
both. A locked read is never served by the L1: it waits for every older store
and reads memory, as a 486 locked read cycle does; the locked write updates a
valid line and memory. LOCK-prefixed RMWs never use the cached fast RMW
pipeline. The core's own instruction fetches may still appear on the bus
while `lock` is high. A platform without other masters may leave `lock`
unconnected.

PC9821_z486_MiSTer (as of 2026-10) ties the snoop port off, does not connect
`lock`, and keeps floppy DMA coherent with the whole-L1 flush; its DMA master
does not wait for LOCK#. The locked cycles above matter for atomicity only
once a platform master honours `lock`; the flush-related fixes
(`docs/coherency-audit.md`) matter there today.

## 486 cache controls

CR0.CD, CR0.NW and the page-level PCD bit act on the L1s as on a 486:

| control | effect |
| --- | --- |
| CR0.CD=1 | no new line is allocated (data or code); valid lines keep answering |
| CR0.CD=1, NW=1 | as above, and a write that hits stays in the L1 (no write-through); external snoops are ignored |
| PTE.PCD=1 | a read or fetch miss in that page is one exact-size bus read (data) or an unallocated line (code); hits are still served; the prefetcher's branch-target buffer does not keep its lines |
| CR3.PCD / PDE.PCD | the same for the page-directory / page-table read of a walk |
| PWT | stored in the TLB for TR7 readback; no effect on this write-through L1 |

CD=0 with NW=1 raises #GP(0). Template windows (`DIRECT`/`NO_ALLOC`) remain
the platform's KEN# equivalent and are independent of these bits.

`RESET_CACHE_DISABLED` (default 0) selects the CR0 reset value. A 486 resets
with CD=NW=1 (60000010h); the default keeps the core's historical
caches-enabled reset (00000010h) so firmware that never clears CR0.CD does not
lose the caches. Set it to 1 for the architectural value when the firmware is
known to enable caching.

## Native whole-L1 flush

`cache_flush` is the platform half of a whole-L1 invalidate; the 486 `INVD`
(0F 08) and `WBINVD` (0F 09) instructions are the architectural half and drive
the same controller.

| Port | Meaning |
| --- | --- |
| `cache_flush` (in) | Request input. A **held level is one walk**: the request is consumed once and re-armed only after the input is released, so holding it across `cache_flush_done` does not start a second walk. A one-cycle pulse also works. |
| `cache_flush_busy` (out) | High for the whole walk, from the request through both caches' set walks. |
| `cache_flush_done` (out) | One-cycle pulse when the walk completes. |

One walk covers **both** L1s. The controller first drains the posted store queue
(a store the bus has already accepted cannot fall behind the walk), then sweeps
both caches in parallel.

Each cache's sweep is an **independent walk over its sets**, not a service of
the cache's fill/lookup state machine, and it cancels rather than waits out any
fill in flight: because a fill can be blocked indefinitely behind an unrelated
bus transaction — and the platform asking for the flush may be holding that very
transaction until the flush completes — waiting for the caches to fall idle
would deadlock the machine. A fill that is in flight when the flush is armed is
marked so its install is suppressed (the fetch is still answered; only the line
install is dropped), and the sweep then runs concurrently with it. A walk
therefore **always completes in a bounded number of cycles** regardless of bus
state or cache activity, and no line fetched before the sweep can be installed
after it. A registered snoop yields the sweep a cycle (its clear writes a
different index through the same way RAMs) and the sweep re-issues that set; the
post-reset walk clears everything and never touches the bus, so the sweep may
simply wait for it.

The store drain is the one part of a walk that needs the bus (the drained stores
must be visible in memory before `done`). It cannot deadlock against the flush
because a demand access is only presented after the queue drains, and memory
accesses are served independently of the flush.

The platform path and the instruction path are **separate inputs** and are
arbitrated inside the core rather than ORed at the boundary. Both are latched, so
a request that arrives while a walk is already running starts a following walk
instead of being dropped; a held platform level still counts once and re-arms
only when it is released.

A flush also kills any buffered speculative prefetch line once, on the same
conservative policy as external coherence.

`INVD`/`WBINVD` are privileged: outside CPL0 in protected mode (V86 included)
they fault with `#GP` through the ordinary fault path. Real mode is unaffected.
Both are found in the generated microcode at entry `0x9F3` (`UADDR_INVD`), selected by the
`RECIPE_ACTION_CACHE_FLUSH` entry action, exactly as `INVLPG` uses
`RECIPE_ACTION_INVLPG`.

## Instruction-cache coherence for direct writes

A store into a template `DIRECT` window bypasses the D-cache, so the matching
I-cache line is invalidated (not patched) in the write's first bus-valid cycle.
`NO_ALLOC` needs no such invalidation: it never installs a line. Both paths are
inert — and folded away — when no template window is enabled.

## Debug outputs

| Output | Width | Meaning |
| --- | --- | --- |
| `dbg_CS` / `dbg_EIP` / `dbg_CS_base` | 16 / 32 / 32 | Architectural `CS` / `EIP` / `CS` base mirrors |
| `dbg_pe` / `dbg_vm` | 1 each | `CR0.PE` / `EFLAGS.VM` (protected / v86 mode) |
| `dbg_x87_state` | 32 | x87 command/executor progress packing |
| `dbg_gate_read` / `dbg_gate_addr` | 1 / 32 | One pulse per accepted IDT/IVT gate read, with its linear address |
| `dbg_pf_code` / `dbg_pf_addr` | 3 / 32 | Latched page-fault error code and faulting linear address |
| `dbg_page_fault` | 1 | Page-fault event |
| `dbg_walk_pde` / `dbg_walk_pte` | 32 / 32 | Page walker's last PDE/PTE read |
| `dbg_cr3` / `dbg_eflags` / `dbg_SP` | 32 / 32 / 16 | `CR3`, `EFLAGS` and `SP[15:0]` mirrors |
| `dbg_issue` / `dbg_issue_eip` | 1 / 32 | Instruction-issue pulse and the IP that will execute next |

These taps are **pure observation**: wires for the PC-98 crash recorder, its OSD
debug view and its snapshot window (the IDT/IVT gate address can also select a
memory window for a snapshot). A design that leaves them unconnected loses
nothing — the fitter drops the unused wires — so they cost no area and no pins.

## `cpu_speed_sel`

`cpu_speed_sel` is 2 bits: 0 = full speed, 1 = 15 MHz, 2 = 30 MHz, 3 = 56 MHz.
It selects a fixed execution-rate limit in `cpu_throttle.sv`; memory, peripherals
and the timebases keep running at the full clock, so guest pacing by a CPU delay
loop scales while bus- and peripheral-paced guests do not change.

## 486 feature parameters

| parameter | default | effect |
| --- | --- | --- |
| `RESET_CACHE_DISABLED` | 0 | 1 resets CR0 to 60000010h (CD=NW=1) as a real 486; 0 keeps the historical caches-on reset for firmware that never sets CR0.CD=0 |
| `ENABLE_HW_BREAKPOINTS` | 1 | 0 removes DR0-DR3 address/data matching (about 300-550 ALMs); the registers, GD, BS, BT and task-switch T-bit traps remain |
| `ENABLE_TLB_TEST` | 1 | 0 makes TR6 writes inert (TR3-TR7 stay readable/writable); the TLB test-copy RAMs are then optimized away |
