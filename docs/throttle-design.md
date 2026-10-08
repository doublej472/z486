# CPU-speed throttle: what it does today, and a design that can reach 286 speeds

Status: **design proposal for owner review. Nothing here is implemented.**
Written 2026-10-07 against fork branch `pc98-throttle-fix`. That branch also
fixes the throttle-exposed defects listed in `docs/fork-rebase-policy.md`,
"Defects found while folding".

The owner wants a CPU-speed selector that can slow the PC-9821 core's CPU down
to 80286 levels for legacy PC-98 games that time themselves by instruction
speed, with several speeds in between and full speed at the top. This document
covers how the current throttle works and what it really delivers, what the
targets should be, what "speed" can mean and how accurate each meaning is, how
a design can stay independent of `clk_sys` and be correct by construction, and
the cost. It ends with a recommendation and the open questions.

## 1. The current mechanism

### 1.1 How it works

`cpu_throttle.sv` (60 lines) is a debt accumulator. It takes a 2-bit
`speed_sel` and a compile-time `CLOCK_RATE_MHZ`, and sets the target to
15, 30 or 56 MHz for settings 1, 2 and 3. Setting 0 means full speed.

- In every *active* cycle the debt grows by `CLOCK_RATE_MHZ - target`. A cycle
  is active when `z486.sv` asserts `throttle_active_cycle`: an issue, or
  `uc_active && !stall`, and the CPU is not parked.
- In every held cycle the debt shrinks by `target`.
- `hold` is set while `debt >= target`.

In steady state the CPU is active for `target / CLOCK_RATE_MHZ` of the cycles
it does not spend stalled on memory or I/O. The debt is 16 bits wide and
saturates at 0xFFFF.

The only lever is the **park**, `throttle_parked_r` in `z486.sv`. When the
predecessor instruction retires its last word (`i_rni_delay`) while `hold` is
set, the successor that is already decoded in D2 is held out of EX. The park
adds terms to `d2_ready`, `uc_slot_live` and `mem_op_eligible`. There are two
special cases:

- `throttle_atomic_chain` keeps a load/POP commit or a PUSH and its delay slot
  together.
- `release_cycle` lets D2 launch in the last repayment cycle.

`cpu_speed_sel` is a z486 input. On the PC-9821 core it is currently tied to
0: the OSD field was withdrawn on 2026-09-27 (the core's todo item 83, and
`docs/z486-local-patch.md` §28). The rate stays independent of `clk_sys`
because `CLOCK_RATE_MHZ = SYS_FREQ / 1e6` is passed down from the profile.
With the base profile at 50 MHz, the 56 MHz setting folds to full speed, so
only two of the three throttled positions do anything there.

### 1.2 What "speed" it really delivers

I measured this in `tb_protected_mode` (`CLOCK_RATE_MHZ` 85, the bench's
default memory latency) with a real-mode program. Each case is 1000
iterations, bracketed by reads of the testbench cycle counter on port 0xFC.
The numbers are z486 clocks.

| loop (1000 iterations) | full speed | setting 1 (15/85, asks 5.67x) | setting 2 (30/85, 2.83x) | setting 3 (56/85, 1.52x) |
|---|---|---|---|---|
| `loop $` | 8049 | 45471 (**5.65x**) | 22739 (2.83x) | 12194 (1.51x) |
| `dec cx / jnz` | 4023 | 28436 (**7.07x**) | 14219 (3.53x) | 6329 (1.57x) |
| `rep stosw` | 4039 | 8517 (**2.11x**) | 6262 (1.55x) | 5216 (1.29x) |
| `rep movsw` | 6038 | 10530 (**1.74x**) | 8269 (1.37x) | 6129 (1.02x) |
| load/add/store/inc/dec/jnz | 11300 | 79437 (7.03x) | 39802 (3.52x) | 19859 (1.76x) |
| `mov/mul/dec/jnz` | 18024 | 102120 (5.67x) | 51060 (2.83x) | 27354 (1.52x) |

Three properties follow from this table:

1. **The rate is exact only for microcoded, boundary-rich code** (`LOOP`,
   `MUL`).
2. **Short hardwired instruction pairs are over-throttled by about 25%**
   (7.07x where 5.67x is asked). The park and release cost a bubble per
   instruction that the accounting does not charge.
3. **REP string instructions are barely throttled** (1.0-2.1x where 5.67x is
   asked). A REP is one instruction, and the park can only act at an
   instruction boundary. The REP body accrues debt the whole time. The 16-bit
   debt then saturates and the excess is forgiven. The core measured the same
   failure at its old 1 MHz position: one 12288-dword `REP STOSD` ran 32.5x
   too fast. On PC-98 machines, REP MOVS/STOS is the standard way to fill and
   scroll the screen.

### 1.3 Why the park is fragile

The park is a second kind of hold, with its own set of clear terms, layered
into the issue, execute and memory-eligibility cones. Every event that drops
the resident D2 word has to release it as well. The first throttled runs of
the protected suite on this branch found the following:

- **An instruction-breakpoint #DB dropped the D2 word but left the park set.**
  This tripped the simulation fuse "throttle parked without a resident D2
  successor". It is now fixed.
- **Changed timing exposed three latent defects:**
  - two ways ring 3 could execute a supervisor-only line;
  - a line-crossing store that missed the branch-target buffer.

  These defects are not in the throttle itself, but the throttle is what
  reached them. Upstream 4bfdde0 has all three.
- **The core's unexplained hang at non-full settings (core todo item 100) is
  still open.** The candidates named there are the one-cycle release pulse,
  a long park that strands an interrupt, and a speed change while parked.
  All three belong to this mechanism.

The core's investigation (todo item 83) also showed that the park cannot be
extended into the middle of an instruction piecemeal:

- freezing `uc_exec` wedges a REP;
- freezing `uc_exec` plus the ROM clock enable wedges the core;
- a "complete" freeze of the sequencer and `stall` collapses ordinary code to
  7141 of 121837 Dhrystone instructions in 40M cycles.

Each of these is a partial freeze. The prefetch, the direct-load tokens and
the VIPT pipeline keep moving underneath the frozen part. **Any correct
mid-instruction slow-down must stop the whole CPU at once.**

## 2. Targets

### 2.1 The PC-98 line's CPUs

| machine | CPU and clock | source | confidence |
|---|---|---|---|
| PC-9801 (1982) | 8086, 5 MHz | Wikipedia, PC-9800 series, models table | high |
| PC-9801E/F/M | 8086-2, 5 or 8 MHz | same | high |
| PC-9801VM | NEC V30, 10 MHz | same | high |
| PC-9801VX | 80286, 8 MHz (10 MHz in VX01/21/41) | necretro.org "PC-9801 VX"; Wikipedia "8 or 10 MHz" | high |
| PC-9801UX | 80286, 10 MHz | Wikipedia | high |
| PC-9801RX | 80286, 12 MHz (necretro: 10-12) | Wikipedia; necretro "PC 9801 RX" | high |
| PC-9801RA | 80386DX, 16 or 20 MHz (RA21) | Wikipedia; necretro "PC-9801 RA" | high |
| PC-9801RS / DS | 80386SX, 16 MHz | Wikipedia | high |
| PC-9801DA | 80386DX, 20 MHz | Wikipedia | high |
| PC-9801FA | 80486SX, 16 MHz | Wikipedia | high |
| PC-9801BA | 80486DX(2), 40 MHz | Wikipedia ("80486DX @ 40 MHz") | medium (DX2/40 per other listings) |
| PC-9821Ce | 80486SX, 25 MHz | Wikipedia | high |
| PC-9821Ap | 80486DX2, 66 MHz | Wikipedia | high |
| PC-9821Xe10 (owner's) | 486-class (owner) | owner; not found in the sources searched | **owner to confirm the exact CPU and clock** |

Sources: <https://en.wikipedia.org/wiki/PC-9800_series>,
<https://necretro.org/VX>, <https://necretro.org/PC-9801_RX>,
<https://necretro.org/PC-9801_RA>.

Many "too fast" PC-98 titles were written for the V30 (8/10 MHz) and the
286 (8-12 MHz). Many 286 machines also carried a V30 for compatibility, so a
V30-class setting is worth considering beside the 286 settings (see the open
questions).

### 2.2 How much the reference CPUs differ from z486, per instruction

The table below compares reference clocks with what z486 measured in §1.2.
The reference numbers are from the HelpPC 2.10 timing tables (Intel data),
<https://panthema.net/2006/helppc21/HelpPC-2.10-HTML/asm-loop.html> and
neighbouring pages. The REP forms are from the 80286 Programmer's Reference
Manual, Appendix B (`REP MOVS` 5+4n, `REP STOS` 4+3n), recalled with medium
confidence and to be checked against the manual. `m` is the length of the next
instruction, which the 286 refetches after a taken branch (about 2 here).

| loop body | 286 clocks / iter | 486 clocks (Intel) | z486 measured | z486 MHz that matches a **286 at 8 MHz** |
|---|---|---|---|---|
| `loop $` | 8+m, about 10 | 6 | 8.0 | 6.4 |
| `dec cx / jnz` | 2 + (7+m), about 11 | 1+3 | 4.0 | 2.9 |
| `rep stosw` | 3 per word | 4 per dword | 4.0 | 10.7 |
| `rep movsw` | 4 per word | 3 per dword | 6.0 | 12.0 |
| `mov/mul r16/dec/jnz` | 2+21+2+9, about 34 | about 1+13+1+3 | 18.0 | 4.2 |

**A single uniform rate cannot match a 286 across instruction mixes.** The
z486 clock rate that reproduces an 8 MHz 286 varies by about 4x (2.9 to 12 MHz)
over these five common loop shapes:

- the 286 is relatively slow at taken branches, where it refetches;
- the 486 is relatively slow, in clocks, at word string moves;
- MUL sits in between.

A game whose delay loop is `DEC/JNZ` and one whose loop is `LOOP` cannot both
be right at any single uniform setting. This is the central fact for the
design.

## 3. What "speed" can mean

### A. A uniform rate limit (the current idea, done correctly)

The CPU runs a fixed fraction of `clk_sys` edges, spread evenly.

**Accuracy against a 286:** within about ±2x, depending on the loop (§2.2).
Against a slower 486 or 386 it is better, because the per-instruction ratios
are closer: a 486 at 25 MHz really is z486 at about 25 MHz, scaled by z486's
own CPI.

**Failure modes:**

- Fixed-count delay loops land wherever their instruction mix puts them.
- Code that calibrates itself against the PIT (a 1.9968/2.4576 MHz timebase
  the platform keeps at real rate) always self-corrects. For that class a
  uniform rate is enough.
- Memory stays full speed, so bus-bound code (REP, VRAM) runs relatively fast.

### B. Instruction-cost pacing against a reference CPU

Each executed instruction is charged its reference-CPU cost: a 286 cost table
by opcode and form, plus terms for memory operands and taken branches, and a
per-iteration charge for REP. A reference-time accumulator lets the CPU run
only while the charged reference time does not exceed the real time elapsed.

**Accuracy:** as good as the cost table, typically ±10-20% per loop (the `m`
term, effective-address and wait-state details). Each fixed loop in §2.2 lands
within that error of the 286 it targets.

**Failure modes:**

- Table errors for rare forms.
- Self-modifying or prefetch-size-dependent timing tricks (the 286's 6-byte
  queue) are not modelled.
- It needs a per-iteration hook for string instructions, and it needs a way to
  stop the CPU mid-instruction, which is the same primitive as A.

### C. Bus-wait-based slowing

Extra wait states are added to the CPU's memory and I/O accesses. This is
cheap but wrong in the main case: z486 hits its L1 most of the time, so
register and loop code (the delay loops) is untouched while REP and VRAM code
slows a lot. It is the reverse of what §2.2 needs. **Not recommended** as the
mechanism. A small variant may be useful on top of A or B to model a slow
machine's slow bus (see the open questions).

## 4. A correct-by-construction primitive: stop the whole CPU

Both A and B need the CPU to pause anywhere, including mid-REP, without any
architectural effect. The only pause that is architecturally invisible **by
construction** is one where the CPU sees fewer clock edges. Every flop and
memory inside z486 holds its value. The CPU is then exactly a slower 486
attached to faster memory and I/O.

### 4.1 How to gate the CPU

**Option 1 (preferred): a gated global clock.** The platform drives z486 from
a gated copy of `clk_sys` through a Cyclone V clock control block
(`ALTCLKCTRL` with its glitch-free `ena`). The block latches `ena` on the low
phase, so a registered enable is safe. This costs no LABs: the clock buffer is
dedicated silicon, and no RTL inside z486 changes.

**Option 2: an RTL clock enable** on every z486 `always_ff` and memory port.
This is portable and does not use a global clock network, but:

- it touches every sequential block in the fork;
- flops that already have their own enable need an extra AND term;
- the enable net fans out to tens of thousands of flops.

**Its area must be measured, not assumed.** With about 9 free LABs it is a
real risk.

### 4.2 What the boundary needs

z486's inputs are sampled only on enabled edges, so every input that is a
*pulse* has to be held until an enabled edge.

The contract becomes: **a `bus_ce` output (the enable) tells the platform
which `clk_sys` cycles the CPU samples.** Then:

- `ready`, `resp_valid`/`line_resp_valid` with `din`/`line_din`, `snoop_valid`
  and its address, and `nmi` must be held until a cycle with `bus_ce`;
- outputs (`valid`, `addr`, `dout`) are already held until accepted, so
  nothing changes on that side.

The PC-9821 memory dispatcher already registers its responses; holding them
until `bus_ce` is a small change on the platform side. The platform ties the
snoop off, and `intr` is a level. The alternative is a holding register at the
z486 boundary, about 165 flops (32 + 128 data bits, about 17 LABs), so the
platform-side hold is the cheaper choice.

When the throttle is off, `bus_ce` is constant 1 and everything is
cycle-identical to today. That is the release-gate property for full speed:
Dhrystone and the boot golden are unchanged by construction.

### 4.3 What can be deleted

Once the CPU is gated, the park can be deleted:

- `cpu_throttle.sv`;
- `throttle_parked_r`, `throttle_atomic_chain` and `throttle_release_cycle`;
- the park terms in `d2_ready`, `uc_slot_live` and `mem_op_eligible`;
- the event_control fuse.

Those cones are on the timing ladder named in the core's AGENTS.md
(`mem_op_eligible`/`fast_path`), so removing the terms is a small timing win.
It also removes the whole class of defects listed in §1.3.

### 4.4 Interaction with the rest of the machine

- **Interrupts.** The PIC's `intr` is a level, recognised at the next CPU
  boundary in CPU time, exactly as on a slower machine. With an even spread
  there are no long parks, so the latency in real time is the reference CPU's.
  The current park can last up to 65535 cycles (1.3 ms at 50 MHz); this has
  no such gap.
- **DMA and the PIT.** These run on `clk_sys` at real rates, as on a real
  machine whose CPU clock was lower. For the PIT this is the right behaviour.
  For DMA and the bus it is a known difference: memory is relatively fast.
- **Halt and wait loops** behave as on the real machine.
- **Debug.** The core's trace and watchdog keep running on `clk_sys` and see
  CPU signals held between enabled edges. They must count CPU events, not
  `clk_sys` cycles (the core's watchdog `STALL_CYCLES` style defaults need
  that check).

### 4.5 Staying independent of `clk_sys`

The enable comes from a phase accumulator in the platform clock domain.
Per `clk_sys` cycle:

```
acc += F_eff
if acc >= F_sys: acc -= F_sys, ena = 1
else:            ena = 0
```

`F_sys` is the profile's `CLOCK_RATE_HZ`, a compile-time parameter, and
`F_eff` is the setting's effective z486 rate. This is the core's
"rates come from the device" rule: the setting's meaning in MHz does not move
when the profile's `clk_sys` does.

- **Mode A** uses one constant `F_eff` per setting, computed at compile time
  from the profile's frequency (a `localparam` table, not a runtime divider).
  The pattern is Bresenham-even, so the CPU never waits more than
  `ceil(F_sys/F_eff)` cycles for an edge.
- **Mode B** replaces the constant with "enable while
  `charged_ref_time <= elapsed_ref_time`". Elapsed reference time advances by
  `F_ref / F_sys` per cycle, by the same accumulator. Each instruction issue
  (and each REP iteration) adds its table cost. The accumulator saturates
  below its width, with the excess forgiven only at a cap of a few
  microseconds, so a long REP is paced, not clamped.

## 5. OSD selector

Entry 0 must stay Full, by the core's config-less-default rule. Eight entries
fit a 3-bit field.

| pos | label | mode A: z486 effective MHz (to calibrate) |
|---|---|---|
| 0 | Full | gating off |
| 1 | 486 33MHz | about 33 × (z486 to 486 CPI ratio), calibrated on Xe10/Dhrystone |
| 2 | 486 25MHz | as above |
| 3 | 386 20MHz | calibrated (386 CPI is about 1.5-2x the 486's) |
| 4 | 386 16MHz | calibrated |
| 5 | 286 12MHz | from the 286 calibration loop set |
| 6 | 286 10MHz | as above |
| 7 | 286 8MHz | as above |

If mode B is built, positions 5-7 (and an optional V30 8/10 position) would use
the 286 cost table instead of a fixed rate. The labels then become accurate
machine equivalences rather than "486 MHz". Following the core's
`check_cpu_speed_table.py` precedent, a label-to-rate table check should come
back with the field.

## 6. Cost

| piece | area | timing |
|---|---|---|
| Gated clock (ALTCLKCTRL) | 0 LABs; one global clock resource (**fit must confirm one is free**) | adds clock-tree skew between the CPU and platform domains (same clock, small skew; STA-checked). Paths across the boundary must be re-timed in a fit |
| Mode-A enable accumulator (platform) | about 3 LABs (a 27-bit accumulator, a compare, a small constant table) | none on CPU cones |
| Platform hold-until-`bus_ce` | about 1-3 LABs (flags; the data is already registered) | none |
| Delete park and `cpu_throttle` | frees about 3-5 LABs (estimate) and removes terms from `d2_ready`, `uc_slot_live`, `mem_op_eligible` | small positive |
| RTL clock enable instead (option 2) | **unknown; must be priced** with a module-alone probe. Could be tens of LABs where existing enables need merging | enable fan-out must be registered and replicated |
| Mode B: 286 cost table plus accumulator | one M10K (256 × 8, if an M10K is free) plus about 6-10 LABs (cost mux, an issue/REP-iteration hook from z486, a 24-bit accumulator) | the hook is a registered tap of `i_issue`/opcode and the REP uStep, off the critical cones |

Net for mode A with the gated clock: about LAB-neutral or better. Mode B adds
about 10 LABs; the device has about 9 free, so mode B must pay for itself or
wait for area elsewhere.

## 7. Verification

1. **Gating invariance (strong and cheap).** Run the whole protected suite with
   the testbench gating the CPU clock by a random or Bresenham enable, with the
   platform hold modelled. Require identical results and an identical
   retired-instruction trace against ungated runs. This is the CPU analogue of
   the core's `tb_pc9821_sysclk_invariance`. It replaces the throttled pass now
   in `test-release` and checks the "throttled CPU equals CPU" property
   directly.
2. **Rate.** A bench measures the enable fraction per setting and profile.
   It is exact by construction; the bench pins the table.
3. **Calibration loop set.** A DOS probe (`tools/hwprobe` style, `CPUSPEED.COM`)
   times the §2.2 loops plus Dhrystone against the PIT. Run the same binary:
   - on the owner's Xe10, to pin the 486 rows;
   - on the core at each setting;
   - for 286 and V30 targets, against the Intel cost tables, or on a real
     286 or V30 PC-98 if the owner has one.
4. **Mode B.** A per-loop error report (core time against reference time) for
   the loop set and a sample of game delay loops the owner names.

## 8. Recommendation

**Build the gated-clock primitive with mode A, and delete the park.**

- It fixes REP pacing, the over-throttling of hardwired pairs, and the whole
  park bug class at once.
- It is architecturally invisible by construction, so the "throttled CPU
  equals CPU" property becomes a theorem plus an invariance bench instead of a
  hunt for missing clear terms.
- It costs about nothing in LABs with the clock control block.

Calibrate the 486 and 386 positions on the Xe10. **Accept ±2x for the 286
positions in mode A**, or add mode B for them once area allows. Mode B is the
only design that makes a *fixed-loop* 286 game run at 286 speed whatever its
loop shape.

**Alternatives, in order:**

1. Mode A with an RTL clock enable, if no global clock is free (price it
   first).
2. Keep the park, but widen the debt and charge per microcode step. This does
   not fix REP: the park cannot stop mid-instruction, and it keeps the
   fragility.
3. Bus wait states. Wrong direction for loop code (§3C).

## 9. Open questions for the owner

1. Which titles motivate this, and do they time themselves with fixed loops or
   with the PIT or VSYNC? (PIT- and VSYNC-calibrated titles need only mode A.)
2. Is mode A's ±2x at the 286 positions acceptable, or is the 286 cost-table
   mode B wanted? Should a V30 8/10 MHz position be included?
3. Is a global clock buffer free in the MiSTer build for a gated CPU clock?
   (A fit answers this.)
4. Is the platform-side "hold responses until `bus_ce`" change acceptable in
   the memory dispatcher? It replaces today's "respond a cycle after accept",
   which `fix(bus_unit)` on this branch makes optional.
5. Is there a real 286, 386 or V30 PC-98 for calibration, besides the Xe10?
   What exactly is the Xe10's CPU and clock?
6. Should a slow setting also slow the bus (wait states on VRAM and I/O), as a
   real slow machine's bus was slow?
7. Labels: machine names ("286 8MHz") or plain rates?
