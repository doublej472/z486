# Microcode-level verification of fault-delivery hazards

Questions of the form "can a younger instruction's decode corrupt the fault
delivery's address?" are **microcode** questions, not datapath questions.  The
address unit's mask and addend depend on which microwords the delivery actually
executes, and which words run is a property of the ROM.

This document records the method and the results for the hazards the fork has
investigated.  It exists so the next such question is answered by decoding,
not by reading the datapath and guessing.

## Tool

`scripts/ucode_disasm.py` renders annotated listings and scans:

```
scripts/ucode_disasm.py --delivery        # the fault/interrupt delivery path
scripts/ucode_disasm.py --sensitive       # words whose IND mask uses i.addr32
scripts/ucode_disasm.py --find-dest   DES_CS
scripts/ucode_disasm.py --find-aluop  PTGEN
scripts/ucode_disasm.py --find-bus    BUSOP_IND_PLUS_ALU
scripts/ucode_disasm.py --list 8D2-8E3
```

It imports the word layout and reader from `scripts/ucode_optimize.py` (the
single owner of that layout) and takes names from the RTL's own `localparam`
tables in `z486_pkg.sv`, so a listing cannot drift from the decoders.

`ind_ctrl_predecode()` in `ucode_rom.sv` maps `bus` (6 bits) to the IND op and
`dest` (7 bits) to the IND destination class; that mapping is what makes a
listing interpretable.

## The fault-delivery path

`ucode_disasm.py --delivery` shows the routine.

| addr | word | role |
| ---: | --- | --- |
| `8A1` | `ALUJMP_BITS32` | sets 32-bit mode |
| `8AD` | `ALUJMP_BITS16` | **real-mode branch** overrides to 16-bit, then jumps to `8D5` |
| `8D2` | `ALUJMP_BITS32` | **protected branch** re-selects 32-bit before the gate |
| `8D6` | `DEST_EFLAGS`, `alusrc=0x10` | the shared MASK16 literal (interrupt and fault delivery) |
| `8D7` | `BUSOP_IND_SRC` → `DEST_DESCOD` | the IDT gate read; masked by `is_dword` |
| `8D9` | `BUSOP_IND_PLUS_ALU` → `DEST_DESSTK` | frame-push effective address; masked by `pe`/`ss_stack32` |
| `8DA/8DC/8DE` | `BUSOP_WR` → `DEST_OPR_W` | the pushes |
| `8E3` | `DEST_CS`, `op=0`, `ALUJMP_USTEP_FAULT_DONE` | delivery completion |

The two operand-size selects are explicit: a protected-mode delivery runs with
`is_dword=1` (32-bit gate address), a real-mode delivery with `is_dword=0`
(16-bit IVT address).  Both were observed in execution traces.

## Which instruction-derived signals can reach the delivery

The address unit's inputs that come from the latched instruction `i` are
`au_instr_jcc`, `au_exec_addr32` and `au_is_dword`.  Their reach is very
different, and only microcode decode shows that:

- **`au_instr_jcc`** (`i.rel_branch_kind == JCC`) selects `alu_value_hold` over
  `alu_value` as `exec_linear_b` for **every** `INDOP_PLUS_ALU` step.  The
  delivery's frame push at `8D9` is exactly such a step, so a younger Jcc leaks
  its displacement into the push address.  **Fixed** by `a5a581b` (clear
  `rel_branch_kind` on `any_fault_r`), with `pf_store_jcc.asm` as the
  fail-first bench.
- **`au_exec_addr32`** (`i.addr32`) is consulted **only** for
  `INDDEST_DESSEG`, which `ind_ctrl_predecode()` defines as
  `{DEST_DES_ES, DEST_DES_OS, DEST_DES_SR}`.  No delivery word is in that set.
  `--sensitive` lists all 9 affected words (six `DEST_DES_OS` in the general EA
  path, three `DEST_DES_ES` in the string/ES path); none is in `8A0-8E3`.
- **`au_is_dword`** masks `INDOP_SRC`/`INDOP_PLUS_ALU` for `DESCOD`/`DESSTK`.
  The delivery *selects* it (see the table above), so a younger instruction's
  operand size cannot truncate the delivery address.

## Results

| item | question | evidence | outcome |
| --- | --- | --- | --- |
| P1 `pf_store_held` | can a younger read's fault overwrite an older store's latched code/CR2? | 19 `page_fault` pulses across 133 tests, **0** while a previous fault is undelivered; `pf_store_held.asm` already pins the property | not reachable; no bench; sibling's guard targets their different fault-latch structure |
| P2 I$ same-way fill/snoop | is a snoop invalidation dropped by a same-way fill? | `tag_fill_write` requires `!snoop_valid_r` and defers via `fill_tag_wait_r`; `tag_snoop_match` must also be event-qualified, or an old match re-clears a newly refilled line. Both collision and post-refill residency are now tested | design already correct; new regression assertion added to `tb_l1_icache.sv` |
| P3 `conform_dpl_value` | should the conforming-transition CPL come from `cpl` rather than `cs_selector_rpl`? | substituting `cpl` leaves `conforming_cpl`, `conforming_xfer`, `conforming_xfer_rpl` (PE entry with visible CS RPL 11b), the call-gate and PE-entry tests passing; the value only writes the cached CS DPL, which no checked path reads after the CS.RPL-based CPL fix | **not demonstrated**; behaviour guarded, no change |
| P4 `copy_stack_dpl` | can the internal CPL transition run with entry-CPL0 still set? | **Yes**: `pe_entry_iret` enters PE without a far CS reload, then returns to CPL3. COPY_STACK_DPL updates CS.RPL before final DEST_CS, while the old override still forced CPL0 and rejected the new SS. The earlier zero-divergence probe missed this path. | **fixed, fail-first**: clear entry-CPL0 at COPY_STACK_DPL |
| P5 `i.addr32` | can a younger instruction corrupt the delivery address? | decode (no `DESSEG` word in the delivery) + traces of both branches + forcing `au_exec_addr32` to 0 or 1 changes no test | not reachable |

## Notes

- Perturbing an input and observing no test failure is *weak* evidence on its
  own (the suite may not cover the path).  It is used here only as
  corroboration; the decode and the traces are the primary evidence.
- A useful next question in this style: which other AU/segmentation inputs are
  fed from live instruction decode rather than a registered snapshot, and do
  any delivery words consume them.  `init_addr32` is `i_bus.addr32` (the
  *incoming* issue bus), not `i`, so it is a different path from
  `au_exec_addr32`.

## 486 additions to the 80386 CROM

The 486 SX feature work reuses CROM routines wherever their structure already
fits, and adds hardware at decoded points instead of rewriting them:

| point | hook | why |
| --- | --- | --- |
| MOV DRn/TRn (IRF index 0x70) | SBAS / SPCR words store DR0-DR3/TR3-TR7; LBAS / LPCR (predecoded as LBAS) read them | the 80386 IRF slots had no backing; index 0x70 aliased GPR 0 |
| MOV CRn word 361 (`COUNTR <- {PG,PE}`) | NW=1 with CD=0 forces COUNTR=1, taking the routine's own PG-without-PE #GP(0) | a fault raised in the RNI delay slot is not delivered |
| fault body word 899 (`EFLAGS |= RF`) | also sets RF in FLAGSB, the image the body pushes | the 386 body set RF only in the live EFLAGS |
| #DB body word 941 | entered by hardware data/instruction breakpoints (DR6.Bn set by hardware) | shared with the task-switch T-bit trap; TF still enters at 93F (BS) |
| 9F6/9F7 (optimizer-owned) | #AC entry: copy of the #GP(0) entry with SIGMA = 17 - 9 | the 80386 has no #AC |
| 0F 07 | decoder routes to the #UD entry | the CROM's LOADALL is not a 486 instruction |
| 0F 24/26 reg 3-5 | decoder routes to the TR6/TR7 routines | the 80386 PLA rejected TR3-TR5 |
| descriptor-load tails 5D5 / 5DA | the protection PLA sends a descriptor whose A bit is set, or a system descriptor, to copies of the tails without the write (8F8 / 8FA); otherwise the tail calls 8FC-903: locked read of the high dword, OR the new `ALUSRC_CONST_100` (alusrc 0x0A), write, re-read the low dword the callers expect in OPR_R | the 80386 rewrote the high dword on every load, unlocked; a 486 writes only to set a clear A bit, with a locked read-modify-write |
| TSS busy set: task switch 74C/741/74E, LTR 6CA | the busy write moves into locked read-modify-write routines (904-90B task switch, 90C-910 LTR) using the new `ALUSRC_CONST_200` (alusrc 0x0E); the task switch now sets B after saving the outgoing task, on both the save (73F) and no-save paths | the 80386 wrote the high dword read earlier, unlocked; only the outgoing task's busy clear (78E) was locked |
| null selector in a task switch, word 7E6 | no longer writes OPR_R back to GDT[0]+4 | a 486 does not touch GDT[0] |
| 8F8-931 (optimizer-owned) | free words: the 80386 LOADALL routine, unreachable since 0F 07 raises #UD | room for the 486 additions above |
