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
(a store the bus has already accepted cannot fall behind the walk), then walks
both caches in parallel: each latches the request and starts only from idle, so
an in-flight fill from before the flush completes first and its line is
invalidated by the walk that follows. Because the walk is the existing
reset-initialisation walk, no cache datapath or tag-write path changes.

The platform path and the instruction path are **separate inputs** and are
arbitrated inside the core rather than ORed at the boundary. This matters when a
platform holds `cache_flush` until after `cache_flush_done`: an `INVD`/`WBINVD`
becoming active in the next cycle must still start and complete its own walk. A
request seen while a walk is already running is queued, not dropped.

A flush also kills any buffered speculative prefetch line once, on the same
conservative policy as external coherence.

`INVD`/`WBINVD` are privileged: outside CPL0 in protected mode (V86 included)
they fault with `#GP` through the ordinary fault path. Real mode is unaffected.
Both are found in the generated microcode at entry `0x9D9`, selected by the
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
