# Pipeline hazard survey

The DOOM/DOOM2 page faults were not a paging bug: two GPR-arbitration defects
corrupted extended-memory pointers, and DOS/4GW's walker then reported a
genuinely-not-present entry.  This document collects every *other* place in the
core that has the same shape, so the class can be fixed structurally instead of
one symptom at a time.

Everything below is either **proven** (a bench fails without the fix or observes
the hazard), **checked** (read and found sound, with the reason), or
**unverified** (suspected, with the obstacle to proving it).

**Status: pattern P1 is now fixed structurally.**  The register producers are
arbitrated once by `gpr_write_merge.sv`, and the commit path *and* all three
forwarding views are built from that one answer, so they cannot disagree.  See
*Structural fix 1 (done)* below; P2's retirement rules, P4's gate and P6's
coherence checks are also in place.  P3 and P5 remain triage rules, and the
unverified items (A6, A7, A8) still need a bench that can miss.

## How each item was found

1. Root-causing the DOOM faults (`fix(data_unit)` commits).
2. Re-diffing every *correctness* commit of the pre-rebase fork against this
   tree (`git diff 53dc450 backup/fork-main-before-rebase`), because the rebase
   had already dropped one proven fix.  Two independent PC-98 ports exist; the
   sibling (Zet98) names the same defects, so both sets of notes were used.
3. Reading the producer/consumer arbitration in `data_unit.sv`,
   `data_access.sv`, `paging_unit.sv` and the cache units.
4. Two mechanical audits (scripts in `docs/`-adjacent scratch form, see
   *Recommended checks*):
   * every `always_ff` whose reset branch omits a signal its else branch
     assigns;
   * every signal cleared and then set later in the same block (priority arms).
5. One survey bench: `tests/tb_gpr_hazard.sv` (`make test-gpr-hazard`).

## The pattern

**P1 — age order is decided per path, not once.**  Four paths decide who wins a
contested register: the commit block, `gpr_ex_view`, `gpr_ea_view` and
`gpr_capture_view`.  Each hard-codes its own precedence, so they disagree:

| path | precedence | verdict |
| --- | --- | --- |
| commit block | mem token, then load WB, then ROM slot, then EX writes | younger wins (**fixed**) |
| `gpr_ex_view` | load WB, then mem token **overwrites** | **older wins — HAZARD (H1)** |
| `gpr_ea_view` | dly, else shift, else load WB; *no mem-token term at all* | **stale GPR (H3)** |
| `gpr_capture_view` | EX view, then shift, then dly | **inherits H1 (H2)** |

So in the cycle where a younger direct load's write-back lands on a register that
an older deferred load token still owns, the *register* gets the younger value
and *any consumer reading through a view* gets the older one.  Consumers do read
the views in that cycle (M3 ALU operand, byte/word merge base, D2 EA), so this is
a live window, not a theoretical one.

**P2 — deferred producers need an explicit retirement rule.**  The MEM and shift
tokens stay valid until `pipeline_advance` and recommit every stalled cycle.
Any *pulse* producer that lands in between must retire them; the two that exist
today (`load_wb`, a younger fast read replacing `OPR_R`) do.  The hazard is that
this list is by hand: a new pulse producer silently re-opens it (P1 is the same
failure in the combinational path).

**P3 — a verdict must be evaluated in the stage that owns its inputs.**  Three
fixed bugs have this shape (the direct-load segment verdict, the CR3-spanning
walk, the ENTER check-only crossing): a decoupled stage recomputed a verdict
from *live* state that may already belong to a younger instruction.  Every new
verdict consumed by an out-of-order-ish stage needs the same two properties:
evaluated where its inputs belong to the token, and qualified by that token's own
`valid` rather than by a global.

**P4 — reset lists are hand-maintained.**  Five blocks still assign state in
their else branch that they never reset (see inventory).  All five are currently
valid-gated or pre-assigned, so they are latent rather than live, but three of
exactly this shape *were* live (`i_first`, `fault_suppress_delay_slot`,
`any_fault_r`).

**P5 — clear arms are silently overridden by later set arms.**  A signal cleared
under a condition and then set later in the same block keeps the set.  One
instance was a real defect (`i_rni_delay`).  The mechanical scan reports 56
candidates; nearly all are legitimate one-cycle-pulse encodings, so the list is a
triage aid, not a bug list.

**P6 — a cached structure must be invalidated by every writer.**  The store,
snoop, fill, patch and whole-L1-flush paths all write the same tag/data RAMs, and
each new writer is another chance to strand a line.  The fork spent four commits
on this; the surviving design (patch queue merged into fills, snoop/fill
conflict handling, flush that yields to a snoop) is sound in this tree, and the
one red test in the suite turned out to be a bench artifact (see inventory).

## Inventory

### A. Deferred producer vs younger producer (registers)

| id | item | status | evidence |
| --- | --- | --- | --- |
| A1 | commit block gave the write-back to the older deferred token | **fixed** | `tb_load_waw` S1-S5 fail before, pass after; this was the DOOM fault |
| A2 | token recommitted over a younger pulse producer on the next stalled cycle (`load_wb`, replaced `OPR_R`) | **fixed** | `tb_load_waw` S6-S8 fail before, pass after |
| A3 | `gpr_ex_view` / `gpr_capture_view` gave the older token precedence over the younger write-back in the same cycle | **fixed** | `tb_gpr_hazard` H1/H2 fail before (`aaaaaaaa`, older token wins, while the commit read `0000beef`) and pass after; all three views and the commit now come from `gpr_write_merge` |
| A4 | interrupt-entry ROM-slot write vs the token | **checked benign** | `tb_gpr_hazard` H4: both write `OPR_R` to the token's own destination (`recipe_rni`/`hardwired`/`commit_sel` guarantee the same instruction) |
| A5 | an EX GPR write vs a token that outlives it | **unreachable** | `exec`/`uc_exec` is a held level while stalled, so the write re-fires every cycle and the token can never outlive it; `tb_gpr_hazard` H5 is kept as a boundary probe and shows the arbitration alone would clobber |
| A6 | `vipt_load_ex_hit` is gated by the *global* `any_fault`, so a fault could cancel a live token's write-back | **checked sound** | reachability argument: a direct-load token is issued in D2 (one instruction *ahead* of EX), and a load that takes the slow path stalls its own instruction, so no live token can belong to an instruction *older* than the one whose microcode is executing - i.e. the faulting instruction is always older or equal, and cancelling the younger token's write-back is required for precise exceptions.  The fork's own fix here (evaluating the segment verdict in the token's stage) is present |
| A7 | `dly_gpr_forward` (delay-slot write) vs a token, and its position in the views | **unverified** | the EA view ranks dly above shift above load WB, which is not the age order; a bench needs a DLY write with a pending token |
| A8 | OPR_R has three writers (paging demand, `fast_opr_commit`, x87 m32 store); a younger fast read strands an older token's data | **documented** | Zet98's local change list, same base: a younger direct load must be routed to the slow path when an older token owns its destination and `mem_opt_wait` is set.  This tree has the same structure and no such gate |
| A9 | flags: `flag2_*` (registered, one cycle old) vs `sh_flags_commit` (current cycle, per-field write enables) | **checked sound** | both the clocked update and `eflags_fwd` test the shifter commit *first* and it writes only the fields it enables, so the younger producer wins per field and the older one still fills the rest |

### B. Verdict and attribute staleness in decoupled stages

| id | item | status | evidence |
| --- | --- | --- | --- |
| B1 | a walk spanning a CR3 write installed or faulted from the old tables | **fixed** | `tb_protected_mode` `cr3_walk_race*` + `+expect_stale_walk` |
| B2 | direct-load segment verdict read live IND/seg_sel/ROM state, so a younger load could cancel an older write-back | **fixed** | evaluator is per token (`vipt_load_ex_segf`, delivered from `vipt_load_slow_segf_r`); `seg_limit_*` programs |
| B3 | `check_en` for the microcode limit check | **checked sound** | this tree already passes the narrowed form, `.check_en(mem_op_eligible)` — the reason the fork's narrowing was dropped |
| B4 | ENTER's check-only crossing skipped the second page's lookup | **fixed** | `enter_check_cross_pf` program |
| B5 | expand-down (ED) segments inverted the limit verdict | **fixed** | `ed_seg_limit_check` program |
| B6 | the store-path translation sidecar caches a page across CR3/INVLPG | **checked benign** | `st_postable` requires a live `vipt_tlb_hit`, and the TLB (not the sidecar) supplies `st_phys`, so a stale sidecar only costs a skipped preread |
| B7 | `mem_opt_wait` + stale `OPR_R` (Zet98's third item) | **documented, not benchable here** | see A8; `tb_protected_mode` cannot complete a cold-line fill |
| B8 | `st_postable`'s unpaged arm uses a hard-coded VGA compare | **fixed** | disabled whenever any template window is enabled (`!memmap_windows`), so a device window is never posted into the L1 |

### C. Reset and startup state

| id | item | status | evidence |
| --- | --- | --- | --- |
| C1 | `i_first`, `fault_suppress_delay_slot`, `any_fault_r` never reset | **fixed** | reset-guard commit; suites unchanged |
| C2 | `flag2_cf_r/af_r/of_r/result_r/size_r/zsp_r` not reset | **checked latent** | read only when the paired `flag2_*_p` is set |
| C3 | `recipe_state` (`commit_sel`, `hardwired`, `jcc`, ...) not reset | **checked latent** | `hardwired` powers to 0, so no recipe commit is armed at reset |
| C4 | `microsequencer.return_stack` not reset | **checked latent** | only read after a push |
| C5 | `shifter.flags_cf/of/we_zsp/we_of` not reset | **checked latent** | gated by `sh_flags_commit` from a reset FSM |
| C6 | `z486.TMPeIP`/`TMPeSP` not reset | **suspect** | the restart pair is written by the fault entry before use, but an early fault would restart from X in simulation; cheap to reset, worth doing |

### D. Pulse/level priority arms

| id | item | status | evidence |
| --- | --- | --- | --- |
| D1 | `i_rni_delay` re-armed while already armed, extending the pulse | **fixed** | guard added; suites and Dhrystone unchanged |
| D2 | 56 clear-then-set pairs | **triage list** | scan output; the hazard-relevant files (`data_access`, `event_control`, `microsequencer`, `shifter`, `paging_unit`, `bus_unit`) were read and are legitimate pulse encodings.  `paging_unit.walk_cr3_stale_r`, `bus_unit.ext_direct_inval_r` and `shifter.overflow` were bug fixes already carried |

### E. Cache and bus coherence

| id | item | status | evidence |
| --- | --- | --- | --- |
| E1 | D-cache snoop does not invalidate the line | **checked sound** | `dut.tag_way0..3[4]` all zero three cycles after a snoop of `0x40` |
| E2 | `make test-l1-cache` fails at `0x40` | **bench artifact, not a core bug** | identical on unmodified `origin/main`; the failing comparison reads `req_set_r=0`/`tag=0x1402` (the *previous* request) and the RTL trace proves the line was cleared, so the bench's response capture is what is broken.  `cpu_resp_valid` is a clean one-cycle pulse (`req_valid_r` clears as `S_LOOKUP` starts).  Fixing the two handshake defects (drain a response the bench does not own; hold `valid` until `ready`, which the core's contract requires) removes the `0x40` failure, but the bench then hangs in a later task whose *VIPT probe* sequence no longer matches the evolved RTL - so recovering this gate means updating the bench's VIPT model, not the core |
| E3 | I$ patch queue / fill merge / snoop conflict | **checked sound** | `patchq_*` matched into `fill_word_next`, `lookup_snoop_conflict`, `fill_line_snooped_r` all present (upstream design is equivalent to the fork's storeq rewrite) |
| E4 | a snoop that cleared a line mid-fill was reinstated by the fill | **fixed** | `tb_l1_icache` flush-under-stalled-fill case (fails before, passes after) |
| E5 | whole-L1 flush blocked behind an unaccepted direct transaction | **fixed** | independent per-set sweep; `tb_cache_flush`, and the Xe10 pack boot with zero freezes |
| E6 | DIRECT-window write invalidation slot | **checked sound** | one-entry slot plus hold, ported from the fork |

### F. Fault and interrupt delivery

| id | item | status | evidence |
| --- | --- | --- | --- |
| F1 | a fault inside the microcode fault entry was treated as a reset | **fixed** | `event_control` double-fault detection (`tb_z486`/fault programs) |
| F2 | an NMI edge inside the accept window was eaten | **fixed** | `tb_interrupt_nmi` (window edge deferred, delivered after IRET) |
| F3 | `TMPeSP`/`TMPeIP` restart state written by a younger fault | **fixed** (fork FIX #3) | `vipt_load_slow_ssf_r`, `ss_fault_r`, `TmpEIP` handling + benches |

## Benches

| bench | covers | state |
| --- | --- | --- |
| `make test-load-waw` | A1, A2 (commit arbitration, 8 scenarios) | **must pass** - release gate |
| `make test-gpr-hazard` | A4 (H4), A5 (H5), H3 (EA view observation, unchanged by design), and the H1/H2 regression for A3 | **passes** ("no hazards observed"); kept as the place where a new producer/consumer pair gets probed |
| `make test-gpr-merge` | the shared arbitration itself: age order, partial lanes, AH/AL encoding, M3 commit-vs-forward, per-view visibility, commit byte mask | **must pass** - release gate |

## Recommended structural fixes

1. **One age-ordered merge, shared by every path — DONE.**  `gpr_write_merge.sv`
   takes the five in-flight producers (shift token, memory token, interrupt
   writeback slot, direct-load write-back, delay-slot bypass) and produces the
   commit value plus a byte mask, and the three forwarding views.  Design points
   worth keeping:
   * the age order is written down **once**, in the module's port order and in
     `VIS_COMMIT`;
   * a producer is `{lane enable, right-aligned value}` - the same description
     `write_gpr` consumes - so partial-register widths (byte low/high, word,
     dword, AH/AL) cannot drift between the commit and a view;
   * the merge is **per byte**, an independent priority mux per lane, which keeps
     the depth at one mux rather than a chain of word merges (a chain version
     cost 2.8 ns of setup slack; this form does not);
   * views differ only in *visibility*, never in order, and a `translate_off`
     policy check fails the build if a visible producer is not committed or if
     the write-back is ever hidden from a view;
   * an M3 ALU result is committed but never forwarded, because it is derived
     from these views - forwarding it would close a combinational loop.
2. **Fuse the paths together in simulation — DONE.**  The module re-derives all
   four outputs from an independent chain-form reference every cycle, and the
   data-unit commit writes exactly the module's masked value, so a change to one
   path only is a suite failure rather than a game bug.  `tb_gpr_write_merge`
   pins the semantics directly (23 cases, including AH/AL lanes, disjoint lanes,
   the M3 commit-vs-forward split and the commit byte mask).
3. **Automate the reset audit (P4).**  Done: `make check-reset-lists`
   (`scripts/check_reset_lists.py`) fails on any new `always_ff` that assigns
   state its reset branch never resets; today's 19 findings are allow-listed
   with the reason each is safe.  Still worth adding a reset-X sweep
   (`tb_reset_sweep` in the fork) to catch cases only simulation sees.
4. **State the verdict rule once (P3).**  For every verdict consumed by a
   decoupled stage, require (i) evaluation in the stage that owns its inputs and
   (ii) qualification by the token's own `valid`, then assert that no consumer
   sees a verdict whose token is not the oldest.  The three existing fixes are
   instances; A6/B7 are the remaining candidates.
5. **Close the bench gaps (A6, A7, A8).**  Both blocked on the same limitation:
   `tb_protected_mode` ties `line_resp_valid`/`line_din` low, so a cold-line load
   never completes and the optimistic-miss path (`mem_opt_wait`) cannot be
   reached.  A bench with a real line-fill model, or the PC-98 map bench, unblocks
   A6/A7/A8 at once.
6. **Fix the `tb_l1_cache` handshake (E2).**  It is the only red gate in the
   suite.  Its response capture is genuinely broken (two defects, see the E2
   row), but fixing those exposes a stale VIPT-probe model in the same bench, so
   this needs a bench update rather than a core change.

## Survey round 2: feature and property tests

Round 2 attacked the same question from the instruction side instead of the
arbitration side: run a bench first, and only then consider an RTL change.  New
benches live in `tests/programs/`; the ones that currently FAIL are deliberately
not in the `test-protected` gate, so the gate stays green while the finding is
recorded.

### Proven defect

| id | item | status | evidence |
| --- | --- | --- | --- |
| G1 | **`XADD` (0F C0/C1) and `CMPXCHG` (0F B0/B1) are not implemented**; both hang the core instead of executing (a 486-class title or a 486-aware DOS extender that uses them stops dead, and an unimplemented opcode should at worst #UD) | **proven, unfixed** | `min_xadd.asm` and `min_cmp.asm` (one instruction each, register form) time out with the core stuck inside the instruction; `xadd_cmpxchg.asm` covers the full 486 semantics (memory and register forms, flag results, LOCK-prefixed).  Run: `./test_protected_mode.py min_xadd` (or `min_cmp`, `xadd_cmpxchg`) |

`XADD`/`CMPXCHG` are absent upstream as well as in our pre-rebase fork (only
`z486_pkg.sv`'s LOCK-validity tables mention the encodings), so this is a
pre-existing gap rather than a rebase loss.  A sibling PC-98 port implemented
exactly these - "D1 decodes them with the ADD/CMP reg,r/m skeletons and enters
optimizer-owned microcode at 9D1-9EA" - so that port is the reference for a fix:
a decoder entry pair plus the microcode routine, with a fail-first bench already
in place.

### Exclusions (bench exists, behaviour is correct)

| item | bench | result |
| --- | --- | --- |
| pragma balance of simulation-only blocks | `tests/check_pragmas.py` | 59 / 59 balanced in 20 files; no sim-only code reaches synthesis |
| constant columns in the consumed part of the ROM images | `tests/check_rom_columns.py` | none; the constant columns sit outside the consumed slice |
| SHIFT/ SHIFT1 / SHIFT2 / BITTST source pairings in `ucode.hex` | `tests/check_shift_ucode.py` | passed |
| visible real-mode CS and its cached base across `CR0.PE`, in both directions | `pe_cs_visible.asm` | pass |
| entry CPL0 tracked until a CS reload after `CR0.PE` (CR3 access, LGDT) | `pe_cpl0.asm` | pass |
| fault delivery when the faulting instruction immediately follows an issued Jcc (not taken, taken forward, forwarded-flags, taken backward) | `jcc_then_fault.asm` | pass (also checks the #GP error code) |
| OF for 1-bit shifts and rotates, including the SHR (original MSB) and SAR (cleared) rules and the fact that ROL/ROR leave SF/ZF/AF/PF unaffected | `shl1_overflow.asm` | pass |
| the same 1-bit SHL with a DS operand, an ESP operand and a value pushed on the stack (the "chained stack op" case) | `of_stack_vs_ds.asm` | all three identical and correct |

Two of these were nearly reported as bugs before the manual was consulted: the
flags themselves were right, and the expectations were not (the rotates do not
touch SF/ZF/PF, and the flags left by a preceding bench instruction matter).
That is the whole argument for the bench-first rule.

### Still open, and what each needs

| id | item | obstacle |
| --- | --- | --- |
| A7, A8 | delay-slot bypass vs a token; the stale-`OPR_R` gate when a DLY-grace optimistic read misses (`mem_opt_wait`) | needs a bench in which a cold line can actually complete a fill: `tb_protected_mode` ties `line_resp_valid`/`line_din` low, so any miss hangs.  Either add line responses to that bench's memory model or port the fork's PC-98 map bench |
| G2 | instruction fetch from a NO_ALLOC/DIRECT window ("complete uncached instruction lines") | needs a CPU-level bench with the memory-map template enabled (unit coverage exists for `cpu_no_alloc` in `tb_l1_icache`, but not for execution from such a window) |
| E2 | `tb_l1_cache` | the bench's own defects: it does not own its response and releases `valid` before `ready`; repairing those exposes a stale VIPT-probe model in the same bench, so it needs a bench update |
| C6 | `TMPeIP`/`TMPeSP` never reset | latent only (the fault entry writes them before use), and an X-only hazard that a 2-state simulator cannot show |

## Fit check for the shared merge

DE10-Nano OOC CPU fit, 85 MHz, x87 off, 8 KB caches (Quartus 17.0.2 Lite,
`boards/de10nano`, `make cpu CPU_MHZ=85`):

| build | ALMs | registers | setup slack |
| --- | --- | --- | --- |
| before the merge module | 18,882 (45%) | 8,327 | -6.066 ns |
| chain-form merge (rejected) | 19,080 (46%) | 8,125 | **-8.914 ns** |
| byte-priority merge (kept) | 19,037 (45%) | 8,053 | -7.836 ns |

Cost of the kept form: **+155 ALMs (+0.8%)**, **-274 registers**, and 1.77 ns of
setup slack.  The chain form was rejected on timing alone: one whole-word merge
per producer in series added three logic levels to the operand-read and
register-enable cones.  The kept form computes one aligned value and one lane
enable per producer and then selects per byte, which is one mux per byte.

The worst path in the kept fit is *not* in the merge: it is the pre-existing
upstream cone `shifter|flags_cf -> eflags_fwd -> address adder -> esp[29]`, and
the fit is routing-dominated, so most of the 1.77 ns is the area increase rather
than merge depth.  The design was already short of its 85 MHz request before
this change (about 55 MHz), and it is worth the slack here: the merge removes a
proven wrong-value hazard that surfaced as spurious page faults in games.

If that slack is ever unacceptable, the same correctness can be had with zero
cost by keeping the age order in the (cheap, hand-written) view muxes and
retaining this module purely as the simulation-time reference that the fuse
compares against - the order is then still pinned, just not shared.
