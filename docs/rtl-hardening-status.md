# i486 RTL hardening status

Review baseline: `origin/main` 098ab92; fork head before this work: c7157c7.
The fork is reviewed as logical correctness/ISA/integration changes over that
baseline, not as a collection of commit messages presumed correct.

## Current assessment

The known **reproduced** defects from the review and the additional coherence
failures below are fixed, and the self-contained RTL release gate passes.
This is a good local RTL regression state, **not** a claim of complete Intel
486 conformance, FPGA timing closure, or validated NEC firmware/game boot.
No history was rebased or rewritten by this hardening pass.

## Logical changes and their proofs

| change | fail-first observation | permanent test |
| --- | --- | --- |
| End entry-CPL0 at internal COPY_STACK_DPL | outer IRET without initial far CS reload raises unexpected #GP instead of entering CPL3; failure code 21 | `pe_entry_iret` |
| Defer D$ final tag install while a snoop owns its way port | different-set fill drops way-0 clear; read returns 11223344 instead of DEADBEEF | `tb_l1_cache`, both fill widths, snoop trains and later cancellation |
| Mask VIPT hit in registered snoop clear cycle | hit remains asserted while the probe's set is being cleared | `tb_l1_cache` registered probe race |
| Event-qualify I$ snoop matches | idle clocks re-clear a newly refilled line; later read needs another external request | `tb_l1_icache` four-way residency case |
| Arbitrate D-store patch against merged invalidate input | patch becomes consumable while a queued DIRECT invalidate still owns the port | `tb_memory_order` external + DIRECT collision |
| Apply patch backpressure to idle stores too | idle write ready remains asserted while older patch is unconsumed | `tb_l1_cache`; overwrite fuse in `cache_unit` |
| Close all L1 openings at flush arm | pipelined write opening stays ready; separately removing probe masks lets a shared probe remain usable during flush | `tb_l1_cache`; read acceptance masked in both L1s |
| Make physical tag-width macro control the actual tags | with macro=32 but old literal-27 tags, 08000040 aliases 00000040 and reads 44332211 instead of 9ABCDEF0 | `test-l1-tags-wide` |
| Make reset dominate live restart captures | a one-cycle reset on an actual issued instruction leaves TMPeSP=1234 rather than zero | `test-reset-restart`: captures stay in the non-reset arm |
| Repair reset audit and initialize small omitted state | scanner truncates at endcase and reports no omission after it | 14 parser fixtures, explicit 64-item payload inventory |
| Harden release result interpretation | a PASS banner can coexist with a nonzero exit or expected failure | 4 runner fixtures; release uses `--strict` |

The cache writer/flush fixes preserve the single tag-RAM write-port structure.
The D$ stays in S_FILL during deferred tag installation, so no reader can see
old victim tags paired with newly written data. A same-set snoop or flush still
cancels that install. The default physical tag reach remains 27 bits/128 MiB;
32-bit tags are a separately tested configuration, not a default area increase.

Small reset omissions were initialized in scratch registers, width-restore
state, fault latches, restart EIP/ESP, paging request kind, and fill-kill control.
RAMs and valid-gated payloads are not blindly reset; each exception has a named
reason. The scanner audits explicit reset branches, not general four-state
reachability or reset-less pipelines.

## Added instruction/integration guards

- `xadd_cmpxchg_lanes`: AL/AH aliasing, same-register XADD, word memory forms,
  upper-lane preservation, sized arithmetic flags, LOCK memory forms.
- `xadd_cmpxchg_fault`: XADD and both CMPXCHG outcomes on a read-only page; #PF
  code/CR2/EIP, unchanged source/accumulator, restored flags and unchanged memory.
  Invalid register LOCK forms must #UD.
- `pte_cache_coherence`: PTE modification through D$, INVLPG, new-frame read/write,
  and old-frame preservation.
- `rom_pop_vipt_alu`: cold non-flat-SS ROM POP followed by warm VIPT ALU on the
  same destination; result and ESP are checked.
- `test-data-access`: unit-injected older deferred-token condition must bypass a
  nominal hit, wait behind the older demand and return the younger demand's own
  data. Removing the stale-token gate fails this test. It does **not** prove
  that the exact overlap occurs in an integrated instruction sequence.
- `test-pc98-map`: execute and modify code in the DIRECT aperture and NO_ALLOC
  window-0 overlay, plus execute the high firmware alias above the tag reach.
  Both fill widths run. Profile-specific counters prevent an ordinary-map
  simulator from passing these tests accidentally. High alias writes are
  ignored by the test ROM model; no proprietary firmware is supplied.

The missing-486-instruction changes already carried by the fork remain:
XADD/CMPXCHG, INVD/WBINVD, INVLPG and BSWAP. This pass extends their proof where
specified above; it does not claim an exhaustive opcode/exception survey.

## Measured local release gate

Run from the repository root:

```
make -C tests test-release
```

The gate serializes builds because several targets share Verilator support
objects, and tests run under both response models. Latest measured results:

| check | result |
| --- | --- |
| integer/protected directed programs, whole-line responses | 138/138 PASS |
| same programs, narrow responses | 138/138 PASS |
| directed programs with x87 enabled | 146/146 PASS |
| simple instruction cases | 26/26 PASS |
| PC-98 map programs | 3/3 whole-line + 3/3 narrow PASS |
| unit/survey/reset benches | 12/12 PASS; GPR survey has no new findings |
| additional 32-bit-tag L1 benches | 2/2 PASS |
| reset-audit and runner fixtures | 14 + 4 PASS |
| pragma / consumed ROM columns / SHIFT pairing checks | PASS |
| generated microcode/recipes | up to date |
| committed PLA vs fresh generation | 1024 words match, all 4096 mode lanes verified |
| Dhrystone | PASS, **253183 cycles / 121837 instructions / CPI 2.078**, unchanged |

Expected failures cannot be used as release passes. The PLA check generates
into a temporary directory and compares the committed image; regenerating and
then comparing the new image to itself is not the release check.

## What this does not establish

- The external SingleStepTests datasets and `test386.asm/test386.bin` are not
  available in this checkout. The local release gate cannot substitute for
  broad reference-driven architectural conformance tests.
- Current vendor synthesis/timing was not run: Quartus/Vivado are unavailable
  in PATH. Earlier OOC fits already had negative slack at 85 MHz. No current
  timing, area or full-SoC clock-rate guarantee is being made.
- The recorded PC-98 boot-stuck trace describes a refused downstream RAM write;
  these CPU fixes are not proof that that workload is resolved. Real firmware,
  platform/SDRAM admission and game reproductions remain separate validation.
- A7's integrated delay-slot/token collision and the conforming-transition DPL
  question remain **investigative**, not proven failures or falsely closed
  conclusions. The A8 fallback rule has unit/mutation evidence, not an
  integrated fail-first reproduction.

The next evidence step is to run the external architectural datasets and the
owner's full PC-98 boot/game harness with this exact RTL set, then perform the
corresponding timing build. A green local gate must not silently rebaseline
those workload or clock contracts.
