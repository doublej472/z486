# Pipeline hazard inventory

This is a current inventory, not a list of assumptions inherited from the
pre-rebase fork. Treat the fork as logical changes over `origin/main`: retain
correctness fixes with their tests, independently of which historical commit
contained them. The local release entry point is `make -C tests test-release`.

## Evidence vocabulary

- **Fail-first:** a directed test failed before the fix and passes after it.
- **Guard:** an independently expected result already passes; no defect was
  reproduced in that path. A passing guard is not a fail-first proof.
- **Unit injection/mutation:** a pipeline condition is supplied at a module
  interface, or a gate is removed. This tests the local contract, not integrated
  reachability of that condition.
- **Investigative:** no locally reproduced architectural defect. Do not copy
  another core's fix merely because its implementation looks similar.

## Register producers and retirement

`gpr_write_merge.sv` gives deferred shift, deferred memory, interrupt ROM-slot,
load writeback and delay-slot bypass one byte-granular order. Views differ in
visibility, not precedence. M3 ALU results commit but are deliberately not fed
back into their own combinational operand calculation; readers are interlocked.
Recipe STOS/SIGSRC/ESP writes are consolidated in the pulse tier but deliberately
hidden from forwarding, preserving the earlier view contract.

| item | status | test/evidence |
| --- | --- | --- |
| Older deferred load beating younger WB | fixed, fail-first | `test-load-waw` S1–S5 |
| Deferred token recommitting after WB/OPR_R replacement | fixed, fail-first | `test-load-waw` S6–S8 |
| Commit and EX/capture views selecting different winners | fixed, fail-first | `test-gpr-hazard` H1/H2; `test-gpr-merge` |
| Interrupt ROM slot overlapping its own memory token | legal, guard | H4: both write the same OPR_R |
| EX write outliving a token | no integrated defect reproduced | H5 is a unit boundary probe; integrated `exec` is held while stalled |
| M3 result reaching younger partial merge | guard | `vipt_alu_dst_partial` |
| Stale OPR_R forcing a direct token to the slow path (A8/B7) | unit contract pinned | `test-data-access`: normal hit, forced older-token fallback, ordering and returned data; removing the gate fails it |
| Cold ROM POP followed by VIPT ALU on its destination | integration guard | `rom_pop_vipt_alu`, including ESP/result checks |
| Delay-slot bypass and live token on one register (A7) | investigative, not reached | unit order is pinned; the `+monitor_hazards` window monitor never fired in the directed suite or in `test-fuzz` / 90-program soaks |

The attempted A8 instruction program did **not** observe the exact
EX-token/`mem_opt_wait` overlap: UCRD/direct-path eligibility and sequencing
change the route. The unit injection is useful proof of the fallback rule, but
must not be reported as an integrated reproduction. The sibling fuzzer remains
provenance, not local evidence.

`fuzz_gpr_pipeline.py` (`make -C tests test-fuzz`) is the local follow-up: a
seeded, self-checking differential stress over loads, stores, RMW,
partial-register writes, PUSH/POP, LEA, shifts, XCHG, MOVZX/MOVSX, BSWAP,
IMUL, cache flushes and non-flat-segment loads behind stores, each program at
memory latencies 0, 7 and 20, with a corrupted-expectation self-test. Its
`+monitor_hazards` instrumentation reports whether the A7 or A8 window
occurred. In 90 programs neither did, and every result matched the model:
`mem_opt_wait` occurs, but those loads are taken by the UCRD probe or the
crossing path, so no hardwired memory token is live behind them. Both items
therefore remain *not reproduced* rather than *proven unreachable*.

Two deferred-writer invariants are asserted in `data_unit.sv`: a stalled shift
is killed after younger WB, and live shift/memory tokens cannot own overlapping
bytes with no defined age relationship. The interrupt-slot overlap is expressly
allowed, not covered by the sibling core's stricter invariant.

## Verdict ownership, exceptions and privilege

| item | status | test/evidence |
| --- | --- | --- |
| Direct-load segment verdict evaluated from later live state | fixed, fail-first | `seg_limit_*`; verdict captured at EX and delivered by its slow token |
| Expand-down start verdict and D/B upper bound | fixed, fail-first | `ed_seg_limit_check`, `expand_down_b_bit`, `expand_down_stack` |
| Check-only crossing forgetting page two | fixed, fail-first | `enter_check_cross_pf` |
| Prefetch walk spanning a CR3 write | fixed, fail-first | `cr3_walk_race*`, with required stale-walk event |
| Store retry restoring a younger ESP | fixed, fail-first | `cpl3_push_retry`; CALL/PUSHW/ENTER controls |
| Younger branch kind contaminating fault delivery's IND addend | fixed, fail-first | `pf_store_jcc`; microcode analysis in `microcode-verification.md` |
| Visible CS rewritten on PE entry | fixed, fail-first | `unreal_cs_cpl`; PE-entry CPL0 tracked separately |
| PE-entry CPL0 surviving internal COPY_STACK_DPL | fixed, fail-first | `pe_entry_iret`: valid outer IRET without initial far CS reload, then #GP(0) at CPL3 LIDT |
| V86 accesses accidentally promoted by visible CS low bits | fixed, fail-first | `v86_user_page` |
| Microcode-started fault reentry resetting instead of delivering #DF | fixed, fail-first | `gp_double_fault_deliver` |
| NMI edge lost in accept window | fixed, fail-first | `test-interrupt-nmi` |
| New paging demand during registered fault pulse | robustness guard | `vipt_rmw_fault` probe observed redundant walk, not a wrong exception |

Conforming-transition descriptor DPL: `conforming_xfer` is a guard over the
entry-CPL0 paths the question named — a far JMP from the PE-entry state
through an RPL 3 selector, a far CALL at CPL0 through an RPL 3 selector, and a
far CALL from CPL3 through an RPL 0 selector. Each keeps the CPL and sets
CS.RPL to it; the CPL3 case still faults LIDT. No defect was found, so no
protection change was made.

## Coherence

The old conclusion that `test-l1-cache` was a broken bench was **wrong**. The
read-during-clear bug is real, fixed, and that bench is a release gate again.
See `coherency-audit.md` for the paths and the subsequent discoveries:

- D$ different-set/same-way final fill dropping a snoop: tag install now waits
  while the snoop owns the write port. Narrow/wide fills, snoop trains and later
  cancellation of a deferred fill are tested.
- D$ VIPT resolve in the registered clear cycle: masked like the demand lookup.
- I$ held snoop tag match clearing a later refill: the clear is event-qualified.
- D$ patch vs queued DIRECT invalidate: the **merged** invalidate port owns
  arbitration, and idle as well as pipelined stores obey patch backpressure.
- Page-table updates through D$: `pte_cache_coherence` changes a PTE, uses
  INVLPG, observes the new frame and checks that only that frame is written.
- PC-98 DIRECT/window-0 NO_ALLOC instruction fetch and self-modification:
  `test-pc98-map` runs both response widths. High firmware-alias execution also
  verifies that no truncated tag is installed; the test RAM/ROM backing model
  is not a substitute for the owner's NEC firmware or full platform.

## Reset and tooling

The original reset scanner stopped at `endcase` and missed subsequent
assignments. The corrected scanner tokenizes comments/strings and parses
procedural boundaries. Its fixtures cover cases, loops, nested/unbraced and
inverse if/else, member/concatenated/array LHSs, and loud parse failures.

The larger inventory separates valid-gated payloads from control. Small scratch,
restart, fault-latch, width-restore, paging request-kind and fill-kill registers
are now reset. `test-reset-restart` also proves reset dominates captures on a
live instruction's edge (the old i_first otherwise recaptured nonzero ESP over
the reset value). RAMs and valid-gated payloads have named exceptions with reasons;
resetting every data array would defeat FPGA memory inference. The audit covers
**explicit reset branches**, not reset-less datapath pipelines or general
four-state reachability. A true reset-X simulation remains additional evidence,
not something Verilator's two-state PASS proves.

Release tooling requires successful simulator exits, rejects XFAIL configs in
strict mode, gates the GPR survey on its success marker, checks both generated
microcode and the committed PLA image, and records missing external datasets
separately from local passes.

## Historical fit evidence — not a current timing sign-off

Cyclone V OOC CPU, 85 MHz, x87 off; these are earlier measurements, not fits of
the new coherence/privilege/reset changes:

| merge form | ALMs | registers | setup slack |
| --- | ---: | ---: | ---: |
| before shared merge | 18,882 | 8,327 | -6.066 ns |
| chain form, rejected | 19,080 | 8,125 | -8.914 ns |
| byte-priority form | 19,037 | 8,053 | -7.836 ns |
| recipe consolidation + forwarding, rejected | 18,016 | 7,914 | -10.647 ns |
| recipe consolidation + hidden pulse tier, kept | 18,681 | 7,973 | -8.003 ns |

A green RTL gate does not certify timing at 85 MHz, current SoC closure at
50 MHz, or firmware/game boot. Those require the corresponding build and
platform inputs. Current evidence and limitations: `rtl-hardening-status.md`.
