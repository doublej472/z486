# Pipeline hazard survey

The DOOM/DOOM2 page faults were not a paging bug: two GPR-arbitration defects
corrupted extended-memory pointers, and DOS/4GW's walker then reported a
genuinely-not-present entry.  This document collects every *other* place in the
core that has the same shape, so the class can be fixed structurally instead of
one symptom at a time.

Everything below is either **proven** (a bench fails without the fix or observes
the hazard), **checked** (read and found sound, with the reason), or
**unverified** (suspected, with the obstacle to proving it).

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
| A3 | `gpr_ex_view` / `gpr_capture_view` still give the older token precedence over the younger write-back in the same cycle | **HAZARD, proven** | `tb_gpr_hazard` H1/H2: commit reads `0000beef`, views read `aaaaaaaa` |
| A4 | interrupt-entry ROM-slot write vs the token | **checked benign** | `tb_gpr_hazard` H4: both write `OPR_R` to the token's own destination (`recipe_rni`/`hardwired`/`commit_sel` guarantee the same instruction) |
| A5 | an EX GPR write vs a token that outlives it | **unreachable** | `exec`/`uc_exec` is a held level while stalled, so the write re-fires every cycle and the token can never outlive it; `tb_gpr_hazard` H5 is kept as a boundary probe and shows the arbitration alone would clobber |
| A6 | `vipt_load_ex_hit` is gated by the *global* `any_fault`, so a younger instruction's fault can cancel an older token's write-back | **unverified** | upstream `data_access.sv` `if (vipt_load_ex_hit && !any_fault)`; the fork fixed the segment half (evaluated per token) and that half is here.  Needs a two-token/fault overlap bench: `tb_protected_mode` can drive faults but cannot make a *fill* complete (see obstacles) |
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
| E2 | `make test-l1-cache` fails at `0x40` | **bench artifact, not a core bug** | identical on unmodified `origin/main`; the failing comparison reads `req_set_r=0`/`tag=0x1402` (the *previous* request) and the RTL trace proves the line was cleared, so the bench's response capture is what is broken.  `cpu_resp_valid` is a clean one-cycle pulse (`req_valid_r` clears as `S_LOOKUP` starts) |
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
| `make test-gpr-hazard` | A3 (H1/H2), A4 (H4), A5 (H5), H3 (EA view observation) | **expected to report 2 hazards** until P1 is fixed structurally; not a release gate |

## Recommended structural fixes

1. **One age-ordered merge, shared by every path.**  Build the forwarded value
   once per register, oldest producer first, and use that same value for the
   commit and for all three views.  That removes P1 as a possibility rather than
   patching H1/H2 individually.
   A cheaper interim step in the current style: compute the retirement
   *combinationally* (`retire_now = load_wb && dst overlap || opr_fast_commit`)
   and use it — not the registered `recipe_*_killed` — in the commit, the masks
   *and* the views, so the token disappears from every path in the same cycle.
2. **Fuse the paths together in simulation.**  A `translate_off` equivalence
   assertion that every view equals the arbitration the commit path performs
   (the fork's "equivalence guard" style) turns P1 into a suite failure instead
   of a game bug.  The views are already formed once, so this is a comparison on
   live state, not new logic.
3. **Automate the reset audit (P4).**  The scan is ~40 lines; wire it into the
   test build so a new `always_ff` that forgets the reset branch fails.  Add a
   reset-X sweep (`tb_reset_sweep` in the fork) to catch the X cases that only
   simulation sees.
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
   suite; draining/owning the response before the next request should turn it
   green and restore it as a real gate on the D-cache.
