# Fix research: the five confirmed z486 defects

Historical design/research record. Current status and release evidence are in
[`hazard-survey.md`](hazard-survey.md) and
[`rtl-hardening-status.md`](rtl-hardening-status.md); the release gate rejects
XFAILs rather than counting them as passes. The omissions discovered by the
corrected reset audit and the additional cache/privilege fixes supersede any
older broad claim that the core's hazard class was completely closed.

This note records, for each defect that `tb_protected_mode` now proves with a
fail-first `XFAIL` bench, the root cause in our RTL, the robust fix we intend
(not the minimal one), the alternatives rejected, and the expected timing/area
effect.  The goal is one deliberate commit per area rather than a patch that
re-derives the same reasoning later.

The sibling port (`Zet98_486_MiSTer`, `rtl/vendor/z486`) already carries fixes
for four of the five; where its approach is structurally sound the note says so,
and where our tree has diverged it records what a faithful port looks like here.

## 1. Shift Z/S/P read a shared datapath register (`shifter.sv`)

**Bench** `shifter_stack_flags` (fails at case 1; bare shift passes).

**Root cause.** `SHIFT2` writes the barrel result into the shared `SIGMA`
register (`data_unit.sv`, `sigma <= shift_result`), and the shifter's deferred
flags are combinationally derived from the `sigma` input:

```
assign flags_pf = ~^sigma[7:0];
assign flags_zf = shift1_size == 2'd0 ? sigma[7:0] == 8'd0 : ...
assign flags_sf = shift1_size == 2'd0 ? sigma[7] : ...
```

`sigma` is a shared bus with many producers (stack pushes, `SERECO`, MUL/DIV).
A stack instruction chained in the `SHIFT2` cycle writes its own value into
`sigma` on the same edge (`sigma <= stack_dir ? forwarded_esp + stack_delta :
...`), so the flag-retirement cycle reads the stack pointer instead of the
barrel result.  `flags_commit` is already registered one cycle after `SHIFT2`,
so the defect is only in the *source* of the Z/S/P bits.

**Robust fix.** Capture the result privately in the shifter at the same edge,
so the flops never depend on who else drives `sigma`:

```
logic [31:0] flags_result;
logic [1:0]  flags_size;
always_ff @(posedge clk)
    if (exec && is_shift2 && count_nonzero) begin
        flags_result <= result;
        flags_size   <= shift1_size;
    end
assign flags_pf = ~^flags_result[7:0];
assign flags_zf = flags_size == 2'd0 ? flags_result[7:0] == 8'd0 : ...
assign flags_sf = flags_size == 2'd0 ? flags_result[7] : ...
```

This also fixes the second latent case: a following `SHIFT1` setup can change
`shift1_size` before the retirement, so the size must be captured with the
result rather than read live.

**Rejected alternatives.**
* Gate the stack-op `sigma` write so it cannot clash with `SHIFT2`.  This is a
  priority decision on `sigma`'s write port that has to be replicated in every
  producer, and it would suppress a legitimately needed stack value.
* Route the *commit* path around `sigma` instead.  The flags retire a cycle
  after the value is produced, so any live read has the same race; the private
  capture is the only form that is independent of `sigma`'s arbitration.

**Timing/area.** +34 flops and one 34-bit enable; the Z/S/P cones read a
register either way, so depth is unchanged.  The two extracted taps
(`count1_*`) and the barrel are untouched.

## 2. Fault delivery sees a stale relative-branch kind (`z486.sv`)

**Bench** `pf_store_jcc` (control with a MOV successor passes; the Jcc cases
never reach the handler).

**Root cause.** `i` is the latched instruction (`i <= i_bus` on `i_issue`).
The address unit uses two of its fields:

```
.au_branch_relative(i_bus.rel_branch_kind != REL_BRANCH_NONE)
.au_instr_jcc     (i.rel_branch_kind == REL_BRANCH_JCC)
```

`au_instr_jcc` selects `alu_value_hold` over `alu_value` for `INDOP_PLUS_ALU`
(`operand2 = instr_jcc ? alu_value_hold : alu_value`).  The fault-delivery
microcode re-enters the exception-entry cluster and issues `IND = SIGMA +
constant` steps; if `i` still holds a Jcc whose displacement is parked in
`alu_src_r`, the delivery adds that displacement to the IDT/TSS address.  The
fault then reads the wrong gate and never reaches the handler.

**Robust fix.** Retire the branch kind as soon as a fault is registered, in the
same clocked block that latches `i`:

```
end else if (i_issue) begin
    i <= i_bus;
    i.entry_point <= issue_entry;
end else if (any_fault_r) begin
    i.rel_branch_kind <= REL_BRANCH_NONE;
end
if (interrupt_entry)
    i.rel_branch_kind <= REL_BRANCH_NONE;
```

`i_issue` keeps priority (a fault that coincides with an issue belongs to an
older instruction, and the newly issued instruction must keep its own kind);
the clear then holds for every delivery cycle because the delivery is ~20
clocks behind `any_fault_r`.

**Rejected alternatives.**
* Gate `au_instr_jcc` (and/or `au_branch_relative`) with a "delivery active"
  term.  Logically equivalent, but it inserts a term into the `alu_value_hold`
  mux and the IND adder — two of the hottest paths in the AU — for a condition
  that is almost never true.  Clearing the register is off the critical path.
* Clear on `any_fault` (combinational).  `any_fault` is a combinational sum of
  several fault sources; clearing the register from it is needlessly glitchy
  when the registered form is already early enough.

**Timing/area.** One `else if` arm on an existing flop; effectively free.

## 3. Expand-down uses address size and a live selector (`segmentation_unit.sv`)

**Benches** `expand_down_b_bit` (top edge not faulted) and the passing
`expand_down_stack` pin.

**Root cause.** The expand-down verdict is derived twice, both from the wrong
sources:

```
wire [3:0] seg_type_sel = (seg_sel <= SEG_GS) ? desc_cache[seg_sel[2:0]].seg_type : 4'h0;
wire expand_down = !seg_type_sel[3] && seg_type_sel[2];
wire [31:0] ed_max = addr_size ? 32'hFFFF_FFFF : 32'h0000_FFFF;
wire [31:0] ed_diff = ed_max - eff_offset;
wire ed_size_fault = (ed_diff[31:3] == 29'd0) && (ed_diff[2:0] < access_size);
```

* The upper bound is the **segment's D/B bit**, not the instruction's address
  size.  A B=0 segment accessed with `a32` must fault at `0FFFEh + 4`; our
  `addr_size`-derived bound admits it.
* `seg_type_sel` is read from `desc_cache[seg_sel]`, while `seg_limit_r` is
  registered from the *effective* descriptor (`seg_limit_for`/`read_limit_for`,
  including the SS stack-switch which takes the new stack from the CS slot).
  The two can disagree during a stack switch or `descs w` update.

**Robust fix.** Register the expand-down bit and the D/B bit alongside
`seg_limit_r`, from the same descriptor that produces the limit, and derive the
upper-bound fault from a small carry instead of a 32-bit subtractor:

```
reg seg_ed_r, seg_big_r;                 // `seg_limit_r`'s descriptor
wire ed_top_carry = (({1'b0, eff_offset[1:0]} + {1'b0, access_size}) > 3'd3);
wire ed_high_fault = seg_big_r ? (&eff_offset[31:2] && ed_top_carry)
                               : ((eff_offset[31:16] != 16'h0) ||
                                  (&eff_offset[15:2] && ed_top_carry));
wire ed_fault = !start_out_of_bounds || ed_high_fault;
wire pm_limit_fault = pe && !is_dtable && (seg_ed_r ? ed_fault : limit_violated);
```

`seg_ed_r`/`seg_big_r` are set in every arm that sets `seg_limit_r`
(`seg_limit_for(SEG_SS, 0)`, `read_limit_for(...)`, and the CS-slot arm for the
cross-privilege stack switch) via one helper
`ed_big_of(d) = {d.S && !d.seg_type[3] && d.seg_type[2], d.D_B}`.

Our tree additionally duplicates the check for the direct-load token
(`dir_access_size` / `dir_ed_limit_violated` from the segment-verdict fix).
The same helper is instantiated for `dir_access_size`, so the two paths cannot
drift.

**Rejected alternatives.**
* Keep `addr_size` and only fix the descriptor source (or vice versa).  Each
  half is independently observable, so both must move together.
* Suppress the fault in software.  An over-permissive expand-down limit is a
  protection hole, not just a test failure.

**Timing/area.** *Better*, not worse: it removes a 32-bit `ed_max - eff_offset`
subtractor and two wide comparators, replacing them with bit tests and a 2-bit
adder, at the cost of two flops.  This is the one fix expected to reduce area.

## 4. Visible CS clobbered on `CR0.PE` (`z486.sv`)

**Bench** `unreal_cs_cpl` (control at CS 1000h passes; CS 1001h is rewritten to
1000h).

**Root cause.** The `DEST_CR0` arm forces CPL 0 by rewriting the visible
selector:

```
DEST_CR0: begin
    CR0 <= external_dest_value;
    if (external_dest_value[0] && !CR0[0])
        CS[1:0] <= 2'b00;          // visible CS loses its real-mode low bits
end
```

The architectural state after `MOV CR0` sets PE is: visible CS unchanged
(e.g. `1001h` in unreal mode) and CPL 0 until a control transfer reloads CS.
Rewriting `CS[1:0]` loses the visible value (HIMEMX reads it back), and it is
the only reason `cpl` is correct afterwards.

**Robust fix.** Keep privilege state in a dedicated flop and leave CS alone:

```
reg pe_entry_cpl_zero;
wire [1:0] cpl = vm ? 2'd3 : (!pe || pe_entry_cpl_zero) ? 2'd0 : CS[1:0];

DEST_CR0: begin
    CR0 <= external_dest_value;
    if (external_dest_value[0] && !CR0[0])
        pe_entry_cpl_zero <= 1'b1;
    else if (!external_dest_value[0])
        pe_entry_cpl_zero <= 1'b0;
end

DEST_CS: begin
    if (pe && !vm) CS <= {cs_source_value[15:2], cpl};
    else           CS <= cs_source_value;      // real mode / V86: full selector
    pe_entry_cpl_zero <= 1'b0;
end
DEST_USTEP_TASK_CS: begin
    CS <= cs_source_value;
    pe_entry_cpl_zero <= 1'b0;
end
```

The `{cs_source_value[15:2], cpl}` in `DEST_CS` is what makes the first control
transfer after entry establish the *new* RPL rather than inheriting the
preserved real-mode low bits; using the gated `cpl` keeps the two sources of
truth consistent.  The real-mode / V86 arm keeps the full selector, so a
real-mode CS whose low bits are non-zero is not corrupted.

**Rejected alternatives.**
* Keep rewriting `CS[1:0]` and add a shadow `real_cs` for the visible value.
  Two registers for one architectural value guarantees they drift, and every
  reader of visible CS would need to choose between them.
* Force CPL 0 permanently while `pe` — breaks every ring transition.

**Timing/area.** +1 flop and one extra term on the `cpl` mux, which feeds the
segmentation and paging privilege checks.  Those are already multi-term
comparisons; the added OR is shallow.

## 5. V86 accesses treated as supervisor (`z486.sv`)

**Bench** `v86_user_page` (guest reaches a supervisor-only page without
faulting).

**Root cause.** `implicit_supervisor` decides the privilege of an implicit
access (frame pushes during exception delivery, table reads) with:

```
wire implicit_supervisor = mem_is_dtable || (mem_seg_sel == SEG_TR) ||
                           descsw_mode || (vm && CS[1:0] == 2'b00);
```

The `vm && CS[1:0] == 0` term was meant to detect "a ring-0 CS has been loaded
for delivery, so the frame push is supervisor".  A V86 code segment is a
real-mode selector, so any V86 segment whose selector ends in `00` (e.g.
`1000h`) matches, and every normal V86 access is promoted to supervisor
privilege — user pages stop being protected and #PF error codes lose the U/S
bit.

**Robust fix.** Ask the descriptor, not the selector:

```
wire implicit_supervisor = mem_is_dtable || (mem_seg_sel == SEG_TR) ||
                           descsw_mode ||
                           (vm && desc_cache[SEG_CS].DPL == 2'b00);
```

During normal V86 the CS descriptor carries a non-zero DPL, so the term is
false; once exception delivery loads the ring-0 gate target, `DPL == 0` and the
implicit accesses are correctly supervisor.  This is exactly the sibling's
change and I confirmed it flips our bench from XFAIL to PASS.

**Rejected alternatives.**
* Test `cpl == 0` instead.  Circular: `pg_cpl` is what this term feeds.
* Detect "delivery in progress" from the microcode state.  That is a real signal
  but it is not the architectural reason the access is supervisor, and it would
  couple the paging privilege cone to the fault state machine.

**Timing/area.** Swaps a 2-bit selector compare for a 2-bit descriptor compare;
the descriptor cache is already routed to this cone (it feeds `pg_cpl` via
`cpl`/`CS`).  Neutral.

## Combined effect

| Fix | Flops | Combinational |
|---|---|---|
| 1 shifter flags | +34 | neutral (register-sourced either way) |
| 2 branch kind | 0 | +1 `else-if` arm on an existing flop |
| 3 expand-down | +3 | **−** a 32-bit subtractor + comparators, + a 2-bit adder |
| 4 entry CPL0 | +1 | +1 term on the `cpl` mux |
| 5 V86 DPL | 0 | neutral |
| 6 stack-store ESP | +32 | +1 32-bit mux on the restart path |

Net: roughly +70 flops, one 32-bit subtractor removed, and one 32-bit mux
added, with no added depth on any hot cone.  The largest single cost is the
shifter capture, and it replaces a read of a heavily-loaded shared bus with a
read of a private register, which is as likely to help the flag cone as hurt
it.  The stack-store ESP snapshot is only exercised on the write path, so a
full OOC fit should be run once all six land.

## Still unbenched

Two sibling fixes are not reproduced by a bench here: the
`mem_req_to_paging && !page_fault` gate and the chained-store `wr_restart_esp`
snapshot.  Both are real (they fix Linux demand-paging of a stack page), and
both live in the same `z486.sv` region as fix 2, so they should be designed and
committed together.  Until a bench exists they are recorded as open, not ported
on faith.

## Page-fault restart and request ownership

**`wr_restart_esp` is confirmed and now has a fail-first bench**
(`cpl3_push_retry`).  Four ring-3 register PUSHes cross into a not-present
stack page; the ring-0 `#PF` handler runs on the TSS stack, maps the page and
IRETs, and the sequence must land every value in its own slot with
`ESP = start - 16`.  On HEAD it lands `ESP = start - 20`: the retry decrements
ESP a second time.  Applying the sibling's snapshot
(`wr_restart_esp <= i_first ? ESP : TMPeSP` at write issue, restored with
`TMPeIP` on `page_fault && pg_fault_code[1]`) flips the bench to PASS, and no
other fix does.

Controls narrow it to the dword register PUSH specifically.  The same
map-and-IRET retry passes for a ring-3 **load** (`cpl3_retry`), a near **CALL**
(`cpl3_call_retry`), **ENTER 0,0** (`cpl3_enter_retry`) and a **16-bit PUSH**
(`cpl3_pushw_retry`), each checking its own ESP and stack slots.  Only the
32-bit `PUSH r32` restart loses the pre-decrement ESP, so the fix should be
justified against that path rather than the whole store class.

**`mem_req_to_paging && !page_fault` is ported as a guard, and the window is
now reproduced.**  The directed page-fault probes do not show a wrong
exception: `cpl3_push_retry` reports one #PF and `pf_store_held` gets the
ordering right.  But an RTL probe on the existing `vipt_rmw_fault` (a crossing
memory-destination ALU op) shows the window directly.  At the fault pulse
`page_fault` is high *and* the microcode presents a demand (`uc_data_busreq`),
because `raise_perm_fault`/`raise_walk_fault` call `complete_mem_request`,
returning the FSM to `PG_IDLE` in the same cycle it raises the pulse.  Without
the gate the demand is accepted, the unit re-walks and raises a second
`page_fault` pulse; with the gate there is one.  The second pulse does not reach
the handler twice (`fault_seen_r` absorbs it) and the latched `cr2_reg`/
`fault_code` are identical, so the effect is a redundant walk rather than a
wrong exception - hence a guard, not a reproduced correctness failure.
          Cost: +139 ALMs (+0.7%) and +78 registers in the 85 MHz OOC fit, with
setup slack improving from -8.390 to -8.114 ns.  An in-unit variant
(`idle_data_req && !page_fault`, keeping `page_fault` local) was cheaper in area
(+46 ALMs) but regressed slack to -9.470 ns, so the input-side form is used.

## Harness fix found along the way

`test_protected_mode.py` built every page-directory entry with `'RW'`, i.e.
supervisor, even when the mapped PTEs were `'RWU'`.  A user access needs the
U/S bit set in **both** the PDE and the PTE, so every CPL3/V86 benchmark saw its
user pages as supervisor: the first ring-3 fetch after a probe's IRET faulted
with error code `5`.  The PDE is now built `'RWU'` (permissive; the PTE still
restricts, and a supervisor PTE remains inaccessible to user mode).  The full
suite stays green at 129/129, and CPL3/V86 probes now exercise the user path
they were written for.

The V86 stack-fault probe was retired: the pushed value was not found at its
slot even though ESP was right, and the CPL3 probe reproduced the same shape
far more cleanly (and isolated it to the ESP restart).  A V86 frame must also
carry non-null DS/ES/SS or the IRET restores null selectors, which the retired
probe had wrong.
