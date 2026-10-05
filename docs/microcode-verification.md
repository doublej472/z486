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
| P2 I$ same-way fill/snoop | is a snoop invalidation dropped by a same-way fill? | our `tag_fill_write` requires `!snoop_valid_r` and defers via `fill_tag_wait_r`, so a fill cannot race a live clear; a stale `tag_snoop_match` one cycle later only duplicates an already-performed clear | design already correct; new regression assertion added to `tb_l1_icache.sv` |
| P3 `conform_dpl_value` | should the conforming-transition CPL come from `cpl` rather than `cs_selector_rpl`? | substituting `cpl` leaves `conforming_cpl` passing | **not demonstrated**; open question |
| P4 `copy_stack_dpl` | can the `CS[1:0]` copy run with entry-CPL0 still set? | `copy_stack_dpl` fires at `0x891`/`0x92B`, a different microword from every `DEST_CS` write (`0x2F3`, `0x65B`, `0x6A5`, `0x8E3`); invariant probe `CS[1:0] == cpl` shows 0 divergences | consistent |
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
