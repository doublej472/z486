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

## 486SX feature level (second pass)

The target is the Intel486 SX programming model (no FPU, no CPUID). The 80386
CROM and earlier fork already supplied XADD, CMPXCHG, BSWAP, INVD/WBINVD,
INVLPG, CR0.WP, EFLAGS.AC toggling and the GD/BS/BT debug traps. The remaining
architectural gaps were implemented; every row's test fails on the tree at the
start of this pass (the baseline tree, `c7157c7` plus the first pass) and passes
now, except the two guards marked.

| feature | change | test |
| --- | --- | --- |
| DR0-DR3, DR4/DR5 | DR0-DR3 were dropped; MOV DRn,ECX/EDX/EBX also **overwrote EAX** (IRF index 0x70 aliased GPR 0). Real DR0-DR3; DR4/DR5 alias DR6/DR7; 486 fixed bits (DR6 FFFF0FF0, DR7 bit 10) | `dr_regs` |
| CR0 | ET hardwired 1, reserved bits read 0; NW=1 with CD=0 → #GP(0) through the CROM's own invalid-CR0 path; `RESET_CACHE_DISABLED` parameter for the 60000010h reset | `cr0_486` |
| privilege #GP vector | INVLPG/INVD/WBINVD/MOV CRn/DRn/TRn at CPL3 raised **#SS** whenever the last access segment was SS | `cpl3_priv_gp` |
| CR0.CD / CR0.NW / PCD | CD: no allocation, hits kept; NW: write hits stay in the L1, snoops ignored; PTE/PDE/CR3 PCD: uncached miss (single bus read) for data, unallocated fetch for code and the prefetcher's branch-target buffer; walker reads honor CR3/PDE.PCD | `cache_ctrl_486`; `tb_l1_cache`, `tb_l1_icache` |
| #AC alignment check | CR0.AM + EFLAGS.AC + CPL3; word/dword misalignment by linear address, error code 0, restartable; descriptor/TSS/LDT references exempt; limit faults win; new optimizer-owned entry at 9F6 | `align_check` |
| hardware breakpoints | execution breakpoints (fault, RF resumes once), data write and read/write breakpoints (trap; LEN masking, crossing accesses, REP iterations), B0-B3 for disabled matches, BS+Bn together | `debug_bp`, `debug_bp2` |
| RF in fault frames | faults now push RF=1 (the CROM sets it but pushed the pre-instruction FLAGSB); traps and interrupts unchanged | `fault_rf` |
| task-switch debug state | L0-L3 cleared, T bit raises #DB with BT (existing CROM; guard) | `debug_task` (guard) |
| LOCK# | new `lock` output; LOCK prefix, XCHG mem, TSS busy update, INTA pair; locked reads bypass the L1 behind the store queue | `lock_rmw` (+`expect_lock`), `hlt_wakeup_intr_pm` (+`expect_inta_lock`), `tb_l1_cache` |
| test registers | TR3-TR5 no longer #UD; TR6/TR7 drive a real TLB test port (write with way select, lookup with attribute pairs, PL/REP/LRU/PCD/PWT readback); TR5 CTL=11 invalidates the L1s | `test_regs` |
| LOADALL | 0F 07 executed the 80386 LOADALL microcode (hung the CPU); now #UD | `loadall_ud` |
| conforming transfers | entry-CPL0, RPL 3/RPL 0 selectors into conforming code keep the CPL (guard; no change) | `conforming_xfer` (guard) |

Debug slow mode: while any DR7 L/G bit is set the direct load/RMW pipelines
and dead-slot issue are held off and code-breakpoint mode issues only from a
settled idle sequencer, as the 486 itself slows with breakpoints enabled.
Alignment-check mode holds off the direct pipelines the same way. Neither
mode is entered by ordinary code, and Dhrystone is unchanged.

Deliberate limits, all documented where they apply:

- TR3/TR4 and the TR5 line read/write commands are stored but do not access
  the split L1s (the 486's unified cache-test model has no single equivalent).
- Page-table A/D and descriptor accessed-bit updates are not bus-locked.
- NW=1 write hits update the D-cache and patch a resident I-cache line; a later
  I-cache miss reads memory, not the D-cache.
- A data breakpoint on the instruction after MOV SS, or inside INT n, is
  dropped with the suppressed trap rather than delayed.
- UMOV (0F 10-13), SALC and ICEBP behave as on a 486; CPUID, RDTSC/RDMSR/
  WRMSR, RSM, CMOV and CR4 raise #UD (486SX without CPUID).

## Measured local release gate

Run from the repository root:

```
make -C tests test-release
```

The gate serializes builds because several targets share Verilator support
objects, and tests run under both response models. Latest measured results:

| check | result |
| --- | --- |
| integer/protected directed programs, whole-line responses | 152/152 PASS |
| same programs, narrow responses | 152/152 PASS |
| directed programs with x87 enabled | 160/160 PASS |
| simple instruction cases | 26/26 PASS |
| PC-98 map programs | 3/3 whole-line + 3/3 narrow PASS |
| seeded pipeline fuzz (`test-fuzz`, 12 seeds x 3 latencies) | 36/36 PASS, self-test rejects a corrupted expectation |
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

## Out-of-context timing (Cyclone V, 85 MHz)

CPU-only Quartus 17.0.2 fits (`boards/de10nano/scripts/build_cpu.tcl 0 85`,
x87 off) of the tree before this work (`cur0`) and of the 486SX tree, same
seeds. The core missed 85 MHz OOC before this work; the question here is
whether the changes made it worse.

| tree | seeds | worst setup slack (ns) | mean | setup TNS (ns) | ALMs |
| --- | --- | --- | --- | --- | --- |
| before | 1-5 | -7.82, -8.43, -8.39, -8.21, -8.28 | -8.22 | -32.7k to -37.7k | 19,066-19,141 |
| 486SX, defaults | 1-5 | -8.53, -8.47, -8.56, -8.35, -8.12 | -8.40 | -36.1k to -41.7k | 19,965-20,014 |
| 486SX, `ENABLE_HW_BREAKPOINTS=0 ENABLE_TLB_TEST=0` | 1-2 | -7.94, -7.91 | -7.92 | -35.7k to -37.3k | 19,422-19,695 |

- The mean worst-slack difference (0.18 ns) is inside the seed spread
  (0.6 ns within one tree). The critical paths are the same families as
  before (shifter flags → D-cache address, prefetch → `pb_b1_ok_r`); none of
  the new logic is on them. TNS rises about 12% because the breakpoint
  comparators and the TLB test port add near-critical endpoints.
- Area: +900 ALMs (+4.7%) at the defaults. Sharing the TLB walker write index
  with the TR6 write removed about 700 ALMs from an earlier version, and the
  instruction-breakpoint decision is registered off the issue cone.
- Builds that need the area or slack back can set `ENABLE_HW_BREAKPOINTS=0`
  and/or `ENABLE_TLB_TEST=0`. The debug/test registers, GD/BS/BT/T-bit
  traps, cache controls, #AC and LOCK# remain. With both off, exactly
  `debug_bp`, `debug_bp2` and `test_regs` fail; the other 149 directed tests
  pass.
- Performance: Dhrystone cycle count is identical (253183). Ordinary code
  does not enter debug or alignment-check slow mode.

## What this does not establish

- The external SingleStepTests datasets and `test386.asm/test386.bin` are not
  available in this checkout. The local release gate cannot substitute for
  broad reference-driven architectural conformance tests.
- The OOC fits above are the CPU alone with virtual pins; they are not a
  full-SoC timing closure, and the core already missed 85 MHz OOC before this
  work. No full-SoC clock-rate guarantee is being made.
- The recorded PC-98 boot-stuck trace describes a refused downstream RAM write;
  these CPU fixes are not proof that that workload is resolved. Real firmware,
  platform/SDRAM admission and game reproductions remain separate validation.
- A7's delay-slot/token collision and A8's stale-token window were never
  reached by the directed suite or the fuzzer's window monitors; they remain
  *not reproduced*, not *proven unreachable*. The A8 rule keeps its
  unit/mutation evidence. The conforming-transition DPL question is now a
  guard (`conforming_xfer`, `conforming_xfer_rpl`; the mutated value is
  unobservable on those paths).

The next evidence step is to run the external architectural datasets and the
owner's full PC-98 boot/game harness with this exact RTL set, then perform the
corresponding timing build. A green local gate must not silently rebaseline
those workload or clock contracts.
