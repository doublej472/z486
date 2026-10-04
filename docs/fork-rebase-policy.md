# Fork policy: PC-98 integration on top of upstream

This branch is `doublej472/z486` tracking `nand2mario/z486`. It is **rebased**
onto upstream, never merged into it, so the history must stay a linear series of
small, single-purpose commits on top of `origin/main`.

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

## Known hardenings not carried

These are deliberate, recorded omissions - revisit them when a bench can prove
or refute them:

- **Zet98's stale-`OPR_R` gate for a younger direct load.** Zet98 (a parallel
  PC-98 port the same upstream base) suppresses a direct-load EX hit when an
  older deferred memory token targets the same register and its optimistic read
  has already missed (`mem_opt_wait`), because our forwarding view merges
  `opr_r` for the token's bytes and that value is stale until the data returns.
  The structure is present here (`pend_mem_mask`/`gpr_ex_view` in `data_unit`,
  `mem_opt_wait` in `paging_unit`), but `tb_protected_mode` cannot exercise it:
  it ties `line_resp_valid`/`line_din` low, so a cold-line load never
  completes (a minimal cold load times out). Port it together with a bench that
  can miss.
- **Zet98's "queue the D-cache store patches to the I$" (3-deep).** Superseded
  in the fork by the storeq-forwarding rewrite, and here by the DIRECT-write
  invalidate slot plus its hold; only revisit if a snoop-train regression
  reappears.

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
make test-protected          # 105 directed programs (alljson in programs/)
make test-simple             # tb_z486
make test-memmap-template    # z486_cache_map_pkg
make test-cache-flush        # whole-L1 flush controller
make test-paging-walker      # A/D write-back elision
make test-l1-icache          # fill/snoop races
make test-memory-order       # device/store ordering
make test-interrupt-nmi      # NMI latch
make dhrystone               # must PASS; cycles are a regression signal
```

Notes:

- `make test-l1-cache` fails identically on unmodified `origin/main`; it is not
  one of our gates.
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
