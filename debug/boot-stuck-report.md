# z486 (i486-unit rewrite) freezes at the BIOS memory check — upstream report

## Summary

The rewritten `doublej472/z486` core (the "i486 functional units" rebase) boots
the PC-98 Xe10 firmware through the ITF and the early POST, then **freezes at the
"MEMORY 640KB" memory check**: the CPU stops making architectural progress and
spins forever in the interrupt vector table (IVT). The old core did not do this.

The freeze is a **bogus control transfer into the IVT at `0000:0000` that is NOT
an interrupt/exception** (the core's own `dbg_gate_read` tap is low at the
transition), and it is preceded by the architectural EIP executing a backward
"loop" that has **no corresponding backward branch in the code**.

## Repro

Boot the owner's Xe10 ROM pack through the full PC-98 platform (Verilator). The
diagnostic-pack boot (a much smaller, simpler firmware) passes; the real BIOS
freezes. Deterministic.

```
python3 tools/build_pack.py --dumps <xe10 dumps> --rhythm <OPNA_ADPCM.ROM> \
    --sound <SOUND.ROM> --out pc98pack.bin --mem pc98pack.mem
# then boot the pack through pc9821_system (any full-system bench), real backend timing.
```

## Where it freezes

```
FREEZE at cycle 33478542: CS:EIP=0000:000000a8  (unchanged 4,000,000 cycles)
  eflags=00000046  cr3=00000000  SP=0000  page_fault=0  pf_code=0  pf_addr=00000000
  gate_read=0  gate_addr=0000053d
```

`0000:000000a8` is inside the IVT (real-mode vector table at 0000:0000–03FF).
The CPU walked IVT bytes as code (issue trace: `0000:0030,0031,0033,0035` … in a
tight loop, then `00a2,00a5,00a7`, then stuck at `00a8`).

## The transition into the IVT

The architectural `dbg_EIP` (= the `EIP` register, `z486.sv:342`) went from the
BIOS dispatch block **directly to `0000:0002`** with:

```
eflags=00000046  SP=009c  gate_addr=000f8276   (no gate read in the transition)
```

`dbg_gate_read` is 0 at the transition, so this is **not** an INT/IRET/exception
gate; it is a mis-executed JMP/CALL/RET (or a corrupted EIP) that lands at
`0000:0000`.

## The instruction stream immediately before the transition

Architectural EIP (`dbg_EIP`) sequence, oldest first (the last entry precedes the
jump to `0000:0002`):

```
f800:25d3,25d4,25d7,25d9,25db,25dd,25df,25e2,25e4,25e6,25e8,25ea,25f0,25f2,25f5,
f800:25f8,25fb,25fc,25fe,2600,  25fc,25fe,2600,  25fc,25fe,2600,  25fc,25fe,2600,
     25fc,25fe,2600,  25fc,25fe,2600,  2602,2604,260a,260c,260f,2612,2615,2616,
f800:2618,261a,2616,2618,261a,2616,2618,261a,2616,2618,261a,  261c,0145,0148,014b,
f800:261c,261d,2620,2622,2624,2626,2628,262b,262d,262f,  262b,262d,262f,  ...,
f800:2631,2633,2639,263b,263e,2641,2643,2645,2647,264d,264f,2652,2655,2657,
f800:014b,014d,014f,0151,0154,0156,  013f,0142,0145,  25d3,25d4,25d7,...
```

The BIOS block in question disassembles (16-bit, base `f800:25d3`) as:

```
25D3  0000                 add  [bx+si],al
25D5  C70628100000         mov  word [0x1028],0x0
25DB  E9D900               jmp  0x26b7
25DE  C7060A100300         mov  word [0x100a],0x3
25E4  E87200               call 0x2659
25E7  E89B00               call 0x2685
25EA  C70628100000         mov  word [0x1028],0x0
25F0  E9C400               jmp  0x26b7
25F3  C6060D1004           mov  byte [0x100d],0x4
25F8  3BC6                 cmp  ax,si
25FA  7F15                 jg   0x2611          ; forward
25FC  3BD7                 cmp  dx,di
25FE  7F11                 jg   0x2611          ; forward
2600  C7060A100100         mov  word [0x100a],0x1
2606  89361A10             mov  [0x101a],si
260A  893E1C10             mov  [0x101c],di
260E  E9A600               jmp  0x26b7
2611  C7060A100400         mov  word [0x100a],0x4
2617  E85500               call 0x266f
261A  E86800               call 0x2685
...
```

## The anomaly

The EIP stream contains the repeating sequence

```
25fc, 25fe, 2600,  25fc, 25fe, 2600,  ...
```

i.e. `cmp dx,di; jg 0x2611; mov [0x100a],1` executed **as a backward loop
`25fc → 25fe → 2600 → 25fc`**. But the code has **no backward branch anywhere in
this block** — the only branches are the two `jg 0x2611` (both FORWARD to
`0x2611`). The `mov` at `2600` is followed by the next instruction at `2606`; a
correct core must not return to `25fc`.

So the architectural EIP is being driven **backward by ~4 bytes with no matching
branch**, and shortly afterwards the CPU transfers to `0000:0000`.

## Root-cause hypothesis (for upstream)

The strongest explanation is a **frontend / EIP-tracking bug in the rewrite**, in
one of:

- **conditional-jump mis-execution** — the `jg` (near, signed, 2-byte) is being
  taken to a wrong (backward) target, or a taken/not-taken decision is applied to
  the wrong instruction;
- **EIP update granularity** — the `EIP` register (`z486.sv:2530-2548`,
  `EIP <= EIP + i_bus.length`) is being advanced by the *fetch* length rather than
  the *retired-instruction* length, so a stall/redirect mid-instruction leaves the
  architectural IP a few bytes behind, and a later relative branch computes a
  wrong target;
- **redirect/restart interaction** in `core: fix exception prefetch after early
  redirects` / `core: one-clock D1 decode and port-B issue` — a pipeline flush is
  restoring a stale EIP (25fc) instead of the committed one.

The `SP=009c → 0000` progression and the IVT "walk" are consequences of the bogus
`0000:0000` transfer (the stack lives near the IVT), not the cause.

## Data points an upstream fix should reproduce

- `dbg_gate_read == 0` at the bad transfer (rules out gate/INT/IRET delivery).
- `dbg_EIP` executes `25fc→25fe→2600→25fc` with no backward branch.
- `eflags = 0x0046` (PF+ZF), `SP = 0x009c`, real mode (`cr3 = 0`).

## Test assets

The BIOS and disk image are the owner's, at `/home/doublej472/src/pc98-assets`
(bios/xe10 and disks/). The repro bench is
`scratch/tb_pc9821_realboot.sv` (loads the full 1 MiB pack, dumps the EIP stream
and the crash-recorder taps at the transition).

---

## RESOLVED upstream (2026-10-03): cache-flush deadlock, not a frontend bug

The fork fixed this in `8c5a832` — `pc98(cache-flush): make the whole-L1 sweep
independent of cache state`. The commit message reproduces the **same signature**:
`CS:EIP=0000:00a8`, ~33.5M cycles.

**The actual root cause was the whole-L1 flush controller deadlocking, not the
frontend/EIP hypothesis above.** The firmware copies a routine into low RAM with
`rep movsw` and jumps to it; that routine does 16-bit I/O to the cache-control
ports, and the platform only answers those writes after it sees
`cache_flush_done`. The controller waited for each L1 to fall idle before walking
its sets, and a L1 fill can be blocked indefinitely behind the unaccepted direct
(I/O) transaction that is itself waiting for the flush: the I-cache sat in
`S_FILL` with its line request starved behind `ext_direct_req`, the controller
sat in `CF_WALK` forever, and the CPU spun on the I/O write.

**So the `0000:0000..00a8` code above was the firmware's copied low-RAM I/O
routine** (which overlaps the IVT's addresses), not an IVT walk — the EIP trace
was reading a legitimate spin on the un-accepted I/O write. The "backward loop
with no matching branch" observation was the loop of that routine, and the
`dbg_gate_read==0` reading was correct (it was not an interrupt).

**The fix** (both halves match what this report proposed):
1. each L1's sweep is now an independent walk over its sets (`flush_set_r`, one
   set per cycle) that cancels rather than waits out an in-flight fill
   (`fill_killed_r`), so a walk always completes in a bounded number of cycles;
2. the platform request is latched (`cf_plat_pending_r`, symmetric to the
   instruction path's `cf_insn_pending_r`), so a flush seen during a walk is
   queued rather than dropped.

**Verified here after re-vendoring to `8c5a832`:** the real Xe10 pack now boots
past the memory check (no `FREEZE`; the CPU is executing a normal routine at
`0038:13xx`); the z486 suite is 120/120; Dhrystone (`253183 / 121837 / CPI 2.078`)
and the diagnostic boot golden (`CYCLES used=930530`) are byte-identical to the
pre-fix numbers.
