# Memory-map template

The core's non-cacheable windows, A20 masking policy, and no-allocate bound are
a compile-time template, not hard-coded PC/AT constants, so a platform can
declare its own memory map without forking the core. The defaults reproduce the
core's previous hard-coded PC/AT classification exactly.

`z486_cache_map_pkg` (in `z486_cache_map_pkg.sv`) defines the class enum and
the shared window predicates; `memory.sv` owns the window list and A20 masks;
`paging_unit.sv`/`paging_tlb.sv` take `VGA_BASE`/`VGA_TOP`; `l1_icache.sv`
implements the no-allocate fill.

Every bound is a flat scalar parameter and a compile-time constant, so each
comparison folds to a pair of magnitude compares against literals. No runtime
table, no unpacked-array parameters (Quartus Prime Lite 17 rejects those).

## Classes

| Class | Data path | Instruction path |
| --- | --- | --- |
| `CACHEABLE` | ordinary L1 line | ordinary L1 line |
| `DIRECT` | uncached, ordered bus transaction | normal cached fill |
| `NO_ALLOC` | uncached, ordered bus transaction | pass-through fill, no line installed |

Only `NO_ALLOC` changes the instruction path: the cache tag holds
`Z486_L1_PHYS_ADDR_BITS` (27) address bits, so it cannot distinguish an alias
encoding from its RAM twin. The tag reach, `1 << 27` = 128 MiB, is therefore
the highest safe `NO_ALLOC_BOUND` and the default; a bound above it would let
aliasing lines install, and `memory.sv` rejects one in simulation.

The VIPT resolve's own reject inside `l1_cache.sv` still tests the default
`A0000-BFFFF` compare. That only costs a fast-path opportunity: the template's
classification gates the resolve as well, so a moved VGA window is refused by
the class check and a default window that the platform made cacheable is
refused conservatively.

## Parameters (default = PC/AT)

| Parameter | Default |
| --- | --- |
| `A20_MASK_OFF` / `A20_MASK_ON` | `~0x0010_0000` / all ones |
| `VGA_ENABLE` / `VGA_PRE_WRAP` / `VGA_CLASS` | `0` / `1` / `DIRECT` |
| `VGA_BASE` / `VGA_TOP` | `0x000A_0000` / `0x000B_FFFF` |
| `APERTURE_ENABLE` / `_BASE` / `_TOP` | `0` / `0x000A_0000` / `0x000F_FFFF` |
| `ALIAS_ENABLE` / `ALIAS0..2_*` | `0` / PC-98 alias windows |
| `WIN0_ENABLE` / `_BASE` / `_TOP` | `0` / `0x0008_0000` / `0x0009_FFFF` |
| `NO_ALLOC_ENABLE` / `NO_ALLOC_BOUND` | `0` / `0x0800_0000` (tag reach) |

`WIN0_ENABLE` is gated by the runtime `win0_unmapped` input. A later window
overrides an earlier one, so the `NO_ALLOC` bound layers over `DIRECT` windows.
The A20 mask only clears bits [31:20], so `z486_window_match` compares the low
bits on the raw address and only the segment test on the masked address.

`VGA_ENABLE` gates only the template's duplicate VGA window in `memory.sv`.
`paging_unit`/`paging_tlb`/`l1_cache` classify `VGA_BASE..VGA_TOP` as uncached
unconditionally, so `VGA_ENABLE=0` does not make `A0000-BFFFF` cacheable.
`VGA_BASE` must be page-aligned and `VGA_TOP` page-ending; `memory.sv` rejects
anything else in simulation.

## Device-write ordering

Uncached (`DIRECT`/`NO_ALLOC`) accesses drain the posted L1 store queue before
winning the external bus, so a device write cannot overtake an older RAM store.
This matters whenever a device reads memory the CPU wrote: a DMA descriptor
written to RAM and then a doorbell register must reach memory first. VGA is the
exception, because every VGA access already bypasses the posted queue.

The i486-style posted-store path (`st_route`/`st_take` in `data_access.sv`) is
enabled only while **every** template window is disabled. It selects a store for
a same-cycle D-cache post from the hard-coded map (the `A0000-BFFFF` compare
when paging is off, the TLB's VGA bit when it is on) and so cannot see a
template window: a store to a `DIRECT`/`NO_ALLOC` window would be posted into
the D-cache and the device would never see it. With any window enabled, stores
take the classifying demand path instead, which routes them to the bus. This
costs one same-cycle post opportunity per store on such a build, and is the
price of letting the template declare a device window outside `A0000-BFFFF`.

## CPU writes to `DIRECT` windows

The instruction side of a `DIRECT` window is still a normal cached line fill
(only `NO_ALLOC` changes the instruction path). A CPU store to such a window
does not go through the D-cache, so its registered store patch cannot reach the
I-cache. `memory.sv` therefore invalidates (not patches) the matching I-cache
line in the first bus-valid cycle of a `DIRECT`-window write, independent of
external `ready`.

DIRECT launch excludes pending reads and holds the external bus until write
acceptance, so a refill cannot reinstall old data between invalidation and the
write. A later read must observe the accepted write under the platform's bus
ordering contract.

Invalidation, rather than a data patch, is required because the write may be
ignored or transformed by the device: the aperture (`A0000-FFFFF` in the PC-98
preset) contains ROM as well as RAM, and a write to ROM must leave the cached
copy untouched. Invalidating forces the next fetch to re-read the device, which
is correct whether the device kept the data or not.

An external `snoop_valid` write keeps priority on the I-cache invalidate port.
A direct-write invalidate that collides with a snoop waits in a one-entry slot;
the next invalidating DIRECT write cannot launch while that slot is stranded.
D-cache store invalidates use a separate pending slot while snoop/DIRECT
invalidates own the port. The path is inert when every window is disabled:
`dcache_req_is_direct` is then a constant zero, so the invalidate, its pending
slot and the launch hold-off all fold away.

Self-modifying code in a `DIRECT` window follows the same rule as cached RAM:
the core still requires a frontend-flushing branch after the store. The
branch's refetch misses the invalidated line and re-reads the aperture, and the
speculative reference is already killed by the store-address compare in
`prefetch.sv` (`pf_spec_store`), which covers cached and direct stores alike.

## PC-98 preset

`z486_pc98_preset.svh` exposes `` `Z486_PC98_MAP_PARAMS ``:

```systemverilog
z486 #(`Z486_PC98_MAP_PARAMS, .CLOCK_RATE_MHZ(CLOCK_RATE_MHZ)) cpu ( ...
    .win0_unmapped(win0_overlay_is_not_ram), ... );
```

It sets `A20_MASK_OFF = 0x000F_FFFF` (1 MiB wrap), `VGA_PRE_WRAP = 0`, and
enables the aperture (`A0000-FFFFF`), the three aliases, window-0, and the
no-allocate bound. The bound defaults to the 128 MiB tag reach, which keeps the
`0xFFFx_xxxx` aliases out while all RAM below 128 MiB stays cacheable. A
platform that maps devices below 128 MiB can pass a lower bound with
`` `Z486_PC98_MAP_PARAMS_BOUND(bound) `` (for example its RAM top).

## Runtime window changes

When a platform changes `win0_unmapped` (or otherwise remaps a window at
runtime) it must flush/invalidate the affected cached lines: lines cached while
a window was RAM stay resident until invalidated.

The same applies to a platform that remaps a window through hardware the core
cannot see, such as EMS/UMB bank switching: the switch changes which RAM the
window addresses without any CPU store, so the core's own direct-write
invalidate never fires. Such a platform must assert the external snoop
(`snoop_valid`/`snoop_addr`) for every affected line, or otherwise invalidate
the I-cache, before executing code through the remapped window.
