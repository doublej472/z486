# Fork policy: PC-98 integration on top of upstream

This branch is `doublej472/z486` tracking `nand2mario/z486`. It is **rebased**
onto upstream, never merged into it, so the history must stay a linear series of
small, single-purpose commits on top of `origin/main`.

Review the branch as a **set of logical changes**, not as authority inherited
from a commit. Our objective is i486 RTL correctness, missing 486 instruction
support and PC-98 interface compatibility. A change called `fix` can itself
need correction; an unchanged upstream path can still contain a defect. Preserve
proofs, refresh incorrect conclusions, and do not confuse a passing unit model
with a whole-PC-98 firmware or hardware validation.

## Commit convention

Prefixes:

| Prefix | Meaning |
| --- | --- |
| `fix(<module>):` | A correctness fix to upstream-authored code. Worth upstreaming. |
| `pc98(<area>):` | PC-98-specific behaviour upstream has no reason to carry. |
| `tests:` | Test-only. Safe to drop or reorder during a rebase. |
| `docs:` | Documentation only. |
| `chore:` | Build/plumbing/housekeeping. |

Message bodies use the same four headings so a future rebase can triage a
conflict without re-deriving the reasoning:

```
Why:      the defect or behaviour, and what it breaks.
Upstream: which upstream files/functions this touches. Say explicitly whether
          upstream left the file functionally unchanged (rebases cleanly) or
          rewrote it (expect a conflict).
Test:     the test that proves it - fail-first where one exists, or "guard"
          when it merely pins behaviour that already passes.
Fork:     PC-98 relevance, when there is one.
```

## What we carry, and what we drop

Upstream rewrites the core periodically. A fork fix is only kept when it is
still needed *after* upstream's rewrite, so:

1. **Upstream left the file functionally unchanged** -> keep the fix. The
   commits say so in their `Upstream:` line (e.g. `alu.sv`, `shifter.sv`,
   `mul_div.sv`, `paging_walker.sv`, `interrupt_controller.sv`,
   `l1_icache.sv`).
2. **Upstream rewrote the implementation** -> drop the fix and assume upstream
   fixed it, *unless* a fail-first test still fails without our change. Do not
   port a fix on the strength of the fork's success alone; reproduce it first.
   **Carry the fork's testbenches forward with the same rule, and triage them
   before the RTL.** A dropped bench hides a live defect: the fork's
   `tests/tb_load_waw.sv` and its two-line `data_unit` write-arbitration fix
   were both dropped as "area-campaign" material, and the result was a
   regression that only showed up as spurious page faults in DOS/4KB-extended
   PC-98 games. A dropped *fix* is recoverable; a dropped *proof* is not, so
   when a fork commit mixes area work with a correctness fix, split it and
   re-run the fork's bench from the pre-rebase tag
   (`git show backup/fork-main-before-rebase:tests/<bench>.sv`).
3. **PC-98 product features** (`pc98(...)`) are ours to maintain: the memory-map
   template and the whole-L1 flush. They are ported onto upstream's structure
   rather than copied from the fork, because upstream split `memory.sv` into
   `cache_unit.sv`/`bus_unit.sv` and rewrote most of the core.

## Minimisation triage against 4bfdde0 (2026-10-07)

Every `fix(...)` commit was reverted on the series head (tests kept) and the
release gate re-run; entangled commits were checked against upstream 4bfdde0
directly.  Where upstream's implementation passed the fork's fail-first test,
the fork RTL was dropped and the test kept as a `tests: guard` commit:

- XADD/CMPXCHG: upstream's decoder and routines are used.  Only INVD/WBINVD
  differ (`pc98(ucode)`: the three words at `UADDR_INVD` enter the whole-L1
  flush instead of upstream's no-op).
- SHLD/SHRD and BITTST overflow clear (upstream 6613858 fixed it).
- Deferred shift Z/S/P capture: upstream's `flags_value_r` passes
  `shifter_stack_flags`.
- V86 implicit supervisor: upstream's "VM changed since issue" term passes
  `v86_user_page`.
- The relative-branch-kind clear on fault delivery (`pf_store_jcc` passes).
- The I-cache tag-clear collision mask (`tb_l1_icache` REGISTERED SNOOP RACE
  passes with the later snoop fixes).
- The paging-demand hold during the fault pulse (a guard with no failing test;
  upstream 6613858 fixed the related posted-write case).

The commits that were kept record the failing check in their `Upstream:` line
where the triage was the deciding evidence.  Two kept commits have no failing
test behind them: the NEG CF fix (`neg_size_carry` passes on 4bfdde0, kept by
rule 1 because `alu.sv` is unchanged upstream) and the RNI-delay re-arm guard
(no fail-first test; upstream's set arm is unchanged).

## Known hardenings not carried

These are deliberate, recorded omissions - revisit them when a bench can prove
or refute them:

- **Zet98's "queue the D-cache store patches to the I$" (3-deep).** Superseded
  in the fork by the storeq-forwarding rewrite, and here by the DIRECT-write
  invalidate slot plus its hold; only revisit if a snoop-train regression
  reappears.

The Zet98 stale-`OPR_R` gate for a younger direct load is now carried
(`fix(z486,data_access): route a direct load around a stale OPR_R token`), with
`tb_protected_mode`'s whole-line fill model as the bench; `docs/hazard-survey.md`
records it as A8/B7.

## PC-9821 core local additions (folded 2026-10-07)

The PC-9821 core vendored the fork's pre-rebase tree (8541467) and still
carried 30 test/doc files that the 4bfdde0 rebase did not bring across, plus a
`.gitignore` block.  Each was run against this series and either carried as a
`tests:` commit or dropped:

- **Carried:** `smc_basic`, `smc_same_line`, `smc_store_patch_stress`,
  `ras_same_line_retf` (protected-runner programs), `tb_addr_unit_reloc_equiv`
  (`test-addr-unit-reloc`), `tb_reset_sweep` (`test-reset-sweep`),
  `tb_pc98_map` (`test-pc98-map-bus`), and the `+cpu_speed=N` hook in
  `tb_protected_mode`.
- **`int_vec_telemetry`:** its check is `+expect_vec_fetch` on the
  `dbg_vec_fetch` telemetry this tree does not have; without it the program
  is a plain real-mode INT/IRET, which other programs already cover.
- **`tb_cpu_throttle`, `test-throttled.sh`, `test-throttle-liveness.sh`:**
  written for the fork's old 4-bit OSD-list throttle (`release_request`,
  `+signal_delay_active`, `+speed_wander`).  The liveness program
  (`vipt_load_interlocks` throttled) passes here, but it also passes with
  `throttle_atomic_chain` removed, so it guards nothing on this tree.
- **`tb_mem_resp`:** fails; see the open defects below.
- **`tb_perf_kernels` + `tests/perf/`:** a performance harness probing the
  pre-split `memory.sv` internals and `stall_d2`; a port is a rewrite, and
  Dhrystone is the cycle regression signal.
- **`tb_paging_tlb`:** written against the pre-041d0e1 `paging_tlb` (its
  `live_*` lookup port) and the old sidecar semantics; `tb_paging_tlb_lru`
  covers the PLRU and subset rules.  Its other property - a reset/CR3/INVLPG
  edge drops a same-edge insert whole (`tlb_write`'s `!invalidate_all &&
  !invalidate_page` term) - now has no dedicated bench.
- **`sim_main_cache_flush.cpp`:** the wrapper of the old memory-level
  `tb_cache_flush`; this tree's bench builds with `--binary`.
- **`FOLLOWUP.md`, `docs/pc98-timing-followup.md`:** an unmeasured area wish
  list for the old area campaign, and lab notes on old commits with
  out-of-tree evidence and stale numbers.  The DIRECT-write launch timing they
  describe is in `memmap-template.md`.
- **`.gitignore` LOCAL ADD:** it ignores `tests/programs/*.asm`/`*.json`,
  which this tree tracks, for the core's install-over workflow; it stays the
  core's own local patch.

### Open defects found while folding (RTL unchanged)

- **A line fill cannot take its first response in the accept cycle.**
  `bus_unit` loads the fill's pending-beat counter on the accept edge and
  counts `resp_valid`/`line_resp_valid` only while it is non-zero, so a beat
  (or whole line) presented with `ready` is lost and the fill never
  completes; a DIRECT read does accept it (`!resp_valid` on its pending
  set).  The core's `tb_mem_resp` (adapted to the current ports) passes its
  one-cycle-later responder and fails all eight same-cycle fill cases.  The
  PC-9821 platform avoids it by responding a cycle after accept; the bus
  contract is undocumented either way.
- **The protected suite fails throttled** (`+cpu_speed=1/2/3`; it passes at
  0): `debug_bp`, `debug_bp2`, `debug_ibp`, `debug_task_ibp` stop on the sim
  fuse "throttle parked without a resident D2 successor"
  (`event_control.sv`); `spec_fetch_cpl_leak` reports FAIL at every setting
  (also on upstream 4bfdde0 at setting 3), i.e. the ring-3 jump ran the
  CPL-0-buffered line; `smc_spec_buffer` fails case 4 (the store through a
  linear alias) at 1 and 3; `vipt_rmw_interval` never finishes (TIMEOUT at 20x
  its budget).  `rep_stos_intr`, `rep_scas_intr_high_eip`, `vipt_alu_intr` and
  `io_store_out_in` also fail at some settings, but their stimulus counts
  clock cycles, so those may be harness premises rather than CPU state.

## Rebase procedure

```
git fetch origin
git rebase origin/main          # on the fork branch
```

Expect conflicts in the files upstream rewrites most: `z486.sv`,
`cache_unit.sv`, `memory.sv`, `data_access.sv`, `event_control.sv`,
`segmentation_unit.sv`, `paging_unit.sv`, `l1_cache.sv`, `l1_icache.sv`,
`decoder.sv`, `microsequencer.sv`, `prefetch.sv`, `data_unit.sv`. The
`Upstream:` line in each commit message says whether a given commit touches one.

After the rebase, re-run the gates (below) and re-check the generated artifacts.
If a conflict shows upstream has implemented one of our fixes, drop that commit
with `git rebase --skip` and re-run the gate it owns.

## Gates

```
cd tests
make test-release            # preferred: all self-contained gates, serialized
# Individual gates for triage:
make test-protected          # strict directed programs, x87/PC-98 profiles separate
make test-protected-narrow   # same programs with narrow responses
make test-pc98-map           # actual PC-98 windows, both response widths
make test-pc98-map-bus       # each window's external-port shape, DIRECT I$ invalidate
make test-l1-cache           # D$ snoop/fill/VIPT/patch-backpressure
make test-simple             # tb_z486
make test-memmap-template    # z486_cache_map_pkg
make test-cache-flush        # whole-L1 flush controller
make test-paging-walker      # A/D write-back elision
make test-l1-icache          # fill/snoop races
make test-memory-order       # device/store ordering
make test-load-waw           # deferred-token GPR write arbitration
make test-gpr-merge          # shared GPR producer arbitration
make test-gpr-hazard         # no new survey findings allowed
make test-data-access        # stale-token slow-path contract
make check-reset-lists       # checker self-tests plus named reset exceptions
make check-generators        # microcode/recipes and committed PLA equivalence
make test-interrupt-nmi      # NMI latch
make test-addr-unit-reloc    # address_unit relocation vs independent arithmetic
make test-reset-sweep        # one-cycle reset at every offset of a program
make dhrystone               # must PASS; cycles are a regression signal
```

Notes:

- `test-l1-cache` **is a release gate**. Its earlier exclusion was incorrect:
  the synchronous tag read could hit an entry cleared on the same edge. The
  bench was a correct fail-first proof, not a broken response model.
- The external SingleStepTests datasets and `test386.asm/test386.bin` are not
  bundled. Their absence is a missing validation, not a passing/skipped release
  result. Vendor timing and real PC-98 boot are also separate gates.
- `--strict` rejects expected failures and a PASS banner requires a zero
  simulator exit status. Do not make the release gate green by adding XFAILs.
- Dhrystone is a cycle-exact reference run: a change in its cycle count is a
  behaviour change, so re-baseline it deliberately, never accidentally.
- The microcode and PLA images are generated. After touching
  `scripts/ucode_optimize.py`, `ucode_base.hex` or `pla_entry.svh`:
  `python3 scripts/ucode_optimize.py --check`, and regenerate
  `pla_entry_rom.hex` with `scripts/gen_pla_entry_rom.sv` (it verifies all 4096
  entries itself). Both outputs are committed.
- Simulation-only `$fatal` fuses in `cache_unit.sv` (A20MUX, MEMMAP-UNCACHED,
  MEMMAP-VGA) assert that the default parameter set still reproduces upstream's
  hard-coded classification. They run on the live request stream, so a rebase
  that breaks the default equivalence fails the ordinary suite.
