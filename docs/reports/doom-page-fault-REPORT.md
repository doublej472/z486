# DOOM page fault — z486 core defect: diagnosis and handoff

**Date:** 2026-10-04 · **Status:** mechanism **demonstrated**; causal link to the DOOM fault is the
**leading hypothesis, not proven**. This document is **self-contained**: every piece of RTL,
every capture and every measurement it relies on is quoted inline. No repository access is
assumed.

The core under discussion is the **z486** 486 CPU core (upstream `doublej472/z486`, pinned at
commit `7065221`), vendored into a PC-9821 MiSTer machine. All RTL below is quoted from that
core.

---

## 0. The claim, in one paragraph

DOOM (a 32-bit DOS extender title — DOS/4GW) aborts at startup with an **unhandled page fault at
a fixed instruction** (`CS:EIP = 0008:000009A6`, error code `0000`) while the **data varies**
between runs. That is the signature of a corrupted pointer, not of a missing page. The z486's
register-file arbitration is a known source of exactly this: a prior survey of the core records
**four fixed defects** in that class, one of them annotated *"this was the DOOM fault"*, and
**one still unverified defect (A7)** — the delay-slot bypass overriding younger writers. A7 is
real: driving the core's own arbitration module shows the delay-slot value winning over a
**younger** deferred-load token and over a **younger** load write-back in every forwarding view
that can see both. The remaining gap is a capture of the faulting instruction; §8 states
precisely what is proven and what is not.

---

## 1. The symptom (two captures)

DOS/4GW's own exception printout, two runs, same fault:

```
Exception - 0EH Page fault 0000
   EAX      EBX      ECX      EDX      ESP      EBP      ESI      EDI
000FDF4C 006067F4 00000010 00039A60 0008BB54 000FDF4C 00039A60 0010C66C
   CS   DS   SS   ES       IP     EFLAG   GS   FS
 0008 0010 0D1A 0014 000009A6 00000046 0014 0014
```

```
Exception - 0EH Page fault 0000
   EAX      EBX      ECX      EDX      ESP      EBP      ESI      EDI
00000008 00000002 0000000D 00000000 00086EDC 000002D9 0000049A 0000248A
   CS   DS   SS   ES      EIP     EFLAG   GS   FS
 0008 0010 0D1A 0014 000009A6 00000046 0014 0014
```

(First capture's `EIP` column is printed as `IP`; same field.)

| field | run A | run B | |
|---|---|---|---|
| `CS:EIP` | `0008:000009A6` | `0008:000009A6` | **fixed** |
| `EFLAGS` | `00000046` | `00000046` | **fixed** |
| `SS` | `0D1A` | `0D1A` | **fixed** |
| `DS`/`ES`/`GS`/`FS` | `0010`/`0014`/`0014`/`0014` | same | **fixed** |
| EAX..EDI | `00000008 00000002 0000000D 00000000 00086EDC 000002D9 0000049A 0000248A` | `000FDF4C 006067F4 00000010 00039A60 0008BB54 000FDF4C 00039A60 0010C66C` | **varies** |

Three observations carry the whole case:

1. **The faulting instruction is fixed and the data varies.** So the instruction is a
   legitimate dereference of a pointer whose *value* is sometimes wrong. Nothing about the
   fault address or the page tables is run-dependent in the same way; the *operand* is.
2. **Error code `0000`** = page not present, read, supervisor (kernel). DOS/4GW demand-pages by
   design, so a *not-present* fault is normally handled by its own fault handler; this print is
   the handler giving up.
3. **`EAX == EBP` and `EDX == ESI` in both runs** — the same value in two register pairs. That
   is what a pointer copied into two registers looks like; it also rules out "the register
   number is being decoded wrong" (both copies are wrong *together*, identically, so the fault
   is in the value, not the addressing).

The prior survey of this core states the identical signature for the earlier, fixed, DOOM
faults:

> The DOOM/DOOM2 page faults were not a paging bug: two GPR-arbitration defects corrupted
> extended-memory pointers, and DOS/4GW's walker then reported a genuinely-not-present entry.

## 2. How the captures were taken

The machine is a PC-9821 core on a MiSTer (Cyclone V), running the owner's real Xe10 BIOS ROM
pack to DOS, then DOOM. The core boots to DOS and runs games; the fault reproduces at the same
instruction every run. Register/exception text in §1 is the *guest's own* output, not core
telemetry. The core does contain an instruction-trace ring and a performance/warning telemetry
record streamed over a debug UART; §6 shows why the trace supplied so far does not contain the
fault, and §7 shows that the one datum that would most help (the faulting linear address) is
latched inside the core but never surfaced.

## 3. The RTL under suspicion (verbatim)

The core funnels every register producer through one arbitration module. Four producers can be
in flight simultaneously, at **different architectural ages**.

### 3.1 Producer order (from the module's own header)

```
// Producer order is ARCHITECTURAL age, oldest first, defined here once:
//
//   0 shift-token  deferred destination of the RNI shift result
//   1 memory-token deferred destination of a hardwired load still in flight
//   2 rom-slot     the interrupt-entry writeback slot (OPR_R for the hardwired
//                  load whose RNI the interrupt displaced) - the same write as
//                  the memory token, so their relative order is immaterial
//   3 load-wb      a direct load's write-back; younger than every token,
//                  because a token belongs to the instruction that has not
//                  retired yet while the write-back belongs to its successor
//   4 dly-bypass   the delay-slot write of the instruction that is finishing,
//                  bypassed into the next instruction's D2 address.  View-only:
//                  its architectural commit is an ordinary EX write.
//   5 rep-stos     the REP STOS restartable count (COUNTR -> ECX), ...
//   6 sigsrc       a SIGSRC recipe commit (MOVZX/MOVSX: SIGMA -> SRCREG) ...
//   7 esp          an ESP recipe commit (PUSH: post-push SIGMA -> ESP).
```

Two of those comment lines fix the ages that matter here:

- producer **3**, `load-wb`: *"younger than every token,"* / *"because a token belongs to the
  instruction that has not retired yet while the write-back belongs to its successor"* (one
  comment, wrapped in the source; quoted here as its two lines);
- producer **4**, `dly-bypass`: *"the delay-slot write of the instruction that is **finishing**"*.

The instruction that is *finishing* is the oldest in flight. So `dly` must be **older** than the
memory token (1) and than `load-wb` (3) — i.e. it must **lose** to both. It is numbered **4**,
which the arbitration treats as **younger** than both.

### 3.2 How "younger" is decided — the byte-priority mux (verbatim)

Each of the three views is generated byte-by-byte by an eight-input priority mux; **highest
index wins**:

```systemverilog
always_comb begin : byte_cap
    cap_value[r*32 + b*8 +: 8] = (hit7 && vis_cap[7])  ? pv7[b*8 +: 8] :
                                 (hit6 && vis_cap[6])  ? pv6[b*8 +: 8] :
                                 (hit5 && vis_cap[5])  ? pv5[b*8 +: 8] :
                                 (hit4 && vis_cap[4])  ? pv4[b*8 +: 8] :
                                 (hitv3 && vis_cap[3]) ? pv3[b*8 +: 8] :
                                 (hit2 && vis_cap[2])  ? pv2[b*8 +: 8] :
                                 (hit1 && vis_cap[1])  ? pv1[b*8 +: 8] :
                                 (hit0 && vis_cap[0])  ? pv0[b*8 +: 8] :
                                                         cur[r*32 + b*8 +: 8];
end
```

`hitN` = producer N is valid and its lane enable covers this byte; `pvN` = its value; `cur` = the
register file's current byte. The `ex_value` and `ea_value` blocks are identical with their own
mask. So **the highest-numbered producer whose mask admits it wins the byte.**

### 3.3 The three view masks, as the CPU wires them (verbatim)

```systemverilog
    // Recipe commits stay out of the forwarding views (bits 7:5 clear in all
    // three).  They retire at the RNI edge and are never sampled by a younger
    // consumer in that cycle, so forwarding them buys no correctness and puts
    // their decode on the EA/ALU cone (~2.4 ns of setup slack); the register
    // file still commits them through pulse_value/pulse_wmask below.
    .vis_ex(8'b0000_1010),      // mem, wb
    .vis_ea(8'b0001_1001),      // shift, wb, dly
    .vis_cap(8'b0001_1011),     // shift, mem, wb, dly
```

Bit positions are the producer numbers. So:

| view | producers it can see | comment |
|---|---|---|
| `ex` | 1 (mem), 3 (wb) | does **not** see `dly` |
| `ea` | 0 (shift), 3 (wb), 4 (dly) | does **not** see the mem token |
| `cap` | 0 (shift), 1 (mem), 3 (wb), 4 (dly) | sees **both** `dly` and the mem token |

`cap` is therefore the view where the age-order question is decided.

### 3.4 Where the delay-slot producer comes from (verbatim)

```systemverilog
// Delay-slot GPR write descriptor (a stale recipe slot word writes nothing).
assign dly_gpr_we = i_rni_delay_ea && !recipe_slot_stale &&
                    dly_gpr_we_pre_r;
wire [2:0] dly_gpr_sel  = dly_gpr_sel_pre_r;
wire [1:0] dly_gpr_mode = dly_gpr_mode_pre_r;
gpr_forward_t dly_gpr_forward;
assign dly_gpr_forward.valid = dly_gpr_we;
assign dly_gpr_forward.dst = dly_gpr_sel;
assign dly_gpr_forward.mode = dly_gpr_mode;
assign dly_gpr_forward.data = dly_fwd_value;
```

and it is bound into the arbitration as producer 4:

```systemverilog
    .v_dly(dly_gpr_forward.valid),
    .dst_dly(dly_gpr_forward.dst),
    .mode_dly(dly_gpr_forward.mode),
    .data_dly(dly_gpr_forward.data),
```

`dly_gpr_we` is asserted during the **RNI delay slot** of the instruction that is retiring — i.e.
it carries that (oldest) instruction's result into the next instruction's address stage.

The memory token (producer 1) is the deferred destination of a hardwired load still in flight
(`OPR_R`), and `load-wb` (producer 3) is a direct load's write-back. Both belong to instructions
that have **not** retired, i.e. are younger than the finishing one.

## 4. A7, demonstrated

### 4.1 The probe (complete, self-contained)

Save as `tb_a7.sv` beside the core's `gpr_write_merge.sv` and `z486_pkg.sv`, then build:

```
verilator --binary -Wno-fatal --top-module tb_a7 +incdir+<core dir> \
  tb_a7.sv <core dir>/z486_pkg.sv <core dir>/gpr_write_merge.sv -o tb_a7 && ./obj_dir/tb_a7
```

```systemverilog
`timescale 1ns/1ps
// A7 probe: a DELAY-SLOT write (producer 4) against a YOUNGER memory token
// (producer 1) on the same register, in a view that sees both (vis_cap).
module tb_a7;
  import z486_pkg::*;

  logic [255:0] cur = '0;
  logic         v_shift = 0, v_mem = 0, v_rom = 0, v_wb = 0, v_dly = 0;
  logic         v_stos = 0, v_sigsrc = 0, v_esp = 0, wb_is_alu = 0;
  logic [2:0]   dst_shift = 0, dst_mem = 0, dst_rom = 0, dst_wb = 0, dst_dly = 0, dst_sigsrc = 0;
  logic [1:0]   size_shift = 0, mode_mem = 0, size_rom = 0, size_wb = 0, mode_dly = 0,
                size_stos = 0, size_sigsrc = 0;
  logic [31:0]  data_shift = 0, data_mem = 0, data_rom = 0, data_wb = 0, data_dly = 0,
                data_stos = 0, data_sigsrc = 0, data_esp = 0;

  // The three masks the CPU wires.
  logic [7:0] vis_ex  = 8'b0000_1010;  // mem, wb
  logic [7:0] vis_ea  = 8'b0001_1001;  // shift, wb, dly
  logic [7:0] vis_cap = 8'b0001_1011;  // shift, mem, wb, dly

  logic [255:0] commit_value, commit_wmask, pulse_value, pulse_wmask;
  logic [255:0] ex_value, ea_value, cap_value;

  gpr_write_merge dut (
    .cur(cur),
    .v_shift(v_shift), .dst_shift(dst_shift), .size_shift(size_shift), .data_shift(data_shift),
    .v_mem(v_mem), .dst_mem(dst_mem), .mode_mem(mode_mem), .data_mem(data_mem),
    .v_rom(v_rom), .dst_rom(dst_rom), .size_rom(size_rom), .data_rom(data_rom),
    .v_wb(v_wb), .dst_wb(dst_wb), .size_wb(size_wb), .wb_is_alu(wb_is_alu), .data_wb(data_wb),
    .v_dly(v_dly), .dst_dly(dst_dly), .mode_dly(mode_dly), .data_dly(data_dly),
    .v_stos(v_stos), .size_stos(size_stos), .data_stos(data_stos),
    .v_sigsrc(v_sigsrc), .dst_sigsrc(dst_sigsrc), .size_sigsrc(size_sigsrc),
    .data_sigsrc(data_sigsrc),
    .v_esp(v_esp), .data_esp(data_esp),
    .vis_ex(vis_ex), .vis_ea(vis_ea), .vis_cap(vis_cap),
    .commit_value(commit_value), .commit_wmask(commit_wmask),
    .pulse_value(pulse_value), .pulse_wmask(pulse_wmask),
    .ex_value(ex_value), .ea_value(ea_value), .cap_value(cap_value)
  );

  function automatic [31:0] regval(input logic [255:0] v, input int r);
    regval = v[r*32 +: 32];
  endfunction

  localparam [31:0] TOKEN = 32'h1111_1111;  // producer 1: the YOUNGER deferred load
  localparam [31:0] DLY   = 32'hDDDD_DDDD;  // producer 4: the OLDER finishing insn

  int problems = 0;
  task automatic show(input string what, input [255:0] v);
    $display("  %-28s %08x   %s", what, regval(v, 0),
             (regval(v, 0) === TOKEN) ? "token wins (architectural)" :
             (regval(v, 0) === DLY)   ? "dly wins  <-- A7 HAZARD" : "?");
  endtask

  initial begin
    $display("A7 probe: dly (producer 4, OLDER) vs mem token (producer 1, YOUNGER), EAX");
    v_dly = 1; dst_dly = 3'd0; mode_dly = EA_FWD_D; data_dly = DLY;
    v_mem = 1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = TOKEN;
    #1;
    show("cap  (sees dly+mem)", cap_value);
    show("ex   (sees mem, no dly)", ex_value);
    show("ea   (sees dly, no mem)", ea_value);
    if (regval(cap_value, 0) === DLY) problems++;

    $display("A7 probe: dly vs a YOUNGER load-wb (producer 3), EAX");
    v_mem = 0; v_wb = 1; dst_wb = 3'd0; size_wb = 2'd2; data_wb = TOKEN;
    #1;
    show("cap  (sees dly+wb)", cap_value);
    show("ex   (sees wb, no dly)", ex_value);
    if (regval(cap_value, 0) === DLY) problems++;

    $display("A7 PROBE: %0d hazard(s) demonstrated", problems);
    $finish;
  end
endmodule
```

### 4.2 Result (verbatim)

```
A7 probe: dly (producer 4, OLDER) vs mem token (producer 1, YOUNGER), EAX
  cap  (sees dly+mem)          dddddddd      dly wins  <-- A7 HAZARD
  ex   (sees mem, no dly)      11111111   token wins (architectural)
  ea   (sees dly, no mem)      dddddddd      dly wins  <-- A7 HAZARD
A7 probe: dly vs a YOUNGER load-wb (producer 3), EAX
  cap  (sees dly+wb)           dddddddd      dly wins  <-- A7 HAZARD
  ex   (sees wb, no dly)       11111111   token wins (architectural)
A7 PROBE: 2 hazard(s) demonstrated
```

In **every view that can see both**, the older delay-slot value overrides the younger token /
write-back. `ex` is correct only because it does not see `dly` at all.

### 4.3 Why the existing bench cannot arbitrate this

The core's own arbitration bench pins the *current* behaviour:

```systemverilog
v_dly = 1'b1; dst_dly = 3'd0; mode_dly = EA_FWD_W; data_dly = 32'h0000_3333;
check("7 ea: dly wins low word", regval(ea_value, 0), 32'h2222_3333);
```

so it asserts the thing in question. A directed case with a **pending token** is missing, which
is exactly what the survey says A7 needs.

## 5. The class history (verbatim, from the core's own hazard survey)

> The DOOM/DOOM2 page faults were not a paging bug: two GPR-arbitration defects corrupted
> extended-memory pointers, and DOS/4GW's walker then reported a genuinely-not-present entry.

Inventory of the same shape (registers), oldest defects first:

| id | item | status |
|---|---|---|
| A1 | commit block gave the write-back to the older deferred token | **fixed** — annotated *"this was the DOOM fault"* |
| A2 | token recommitted over a younger pulse producer on the next stalled cycle | **fixed** |
| A3 | `gpr_ex_view`/`gpr_capture_view` gave the older token precedence over the younger write-back | **fixed** |
| A4 | interrupt-entry ROM-slot write vs the token | checked benign |
| A5 | an EX GPR write vs a token that outlives it | unreachable (held level re-fires) |
| A6 | `vipt_load_ex_hit` gated by the global `any_fault` | checked sound |
| **A7** | **`dly_gpr_forward` (delay-slot write) vs a token, and its position in the views** | **unverified** — *"the EA view ranks dly above shift above load WB, which is not the age order; a bench needs a DLY write with a pending token"* |
| A8 | `OPR_R` has three writers; a younger fast read strands an older token's data | **fixed** — ported from a sibling port, annotated *"Doom I floors/ceilings were drawn from stale OPR_R"* |
| A9 | registered flags vs the current-cycle shift-flag commit | checked sound |

So: **four** members of this class were real core bugs, one of them *the* DOOM fault; a further
one (A8) was ported specifically because it degraded DOOM; and **A7 is the only member never
verified**. The verdict below rests on that, plus §4.

## 6. The supplied trace does not cover the fault

The owner supplied an instruction-trace capture (3625 records). Every record is in segment
`F760` — the BIOS (base `0xF7600`, so `F760:181D–182A` = `0xF8E1D–0xF8E2A`) — an 8-instruction
loop repeated ~450 times, ending on dwell `0007`. `0008:000009A6` appears nowhere.

The trace records are `CS:EIP,dwell` lines, e.g.:

```
F760:0000181D,0002
F760:0000181E,0010
F760:00001820,0000
...
F760:0000181E,0007
TRACE END
```

The ring dumps when a trigger fires. The trigger is a single OR:

```systemverilog
assign trace_trig = int21_arena_err | trace_burst_end | trace_flip_trig;
```

None of those terms fires at a page fault, so the ring holds whatever window last matched — here
a BIOS poll loop. **To capture the fault, re-arm the trace on a page fault.** Do *not* trigger on
every page fault: DOS/4GW demand-pages constantly, so the ring would fill with handled faults.
The useful trigger is a fault that **repeats at the same `CS:EIP`** (the handler faulting on its
own delivery path) or the guest's exception-print path.

## 7. CR2 is latched but never surfaced

The core latches the faulting linear address and error code:

```systemverilog
wire [2:0] latched_pf_code;  // Latched page fault error code (for LPCR microcode access)
wire [31:0] latched_pf_addr; // Latched faulting linear address (for LPCR microcode access)
...
assign dbg_pf_code    = latched_pf_code;
assign dbg_pf_addr    = latched_pf_addr;
assign dbg_page_fault = page_fault;
```

and the machine top exposes them:

```systemverilog
    output  [2:0] cpu_dbg_pf_code,    // latched page-fault error code
    output [31:0] cpu_dbg_pf_addr,    // latched faulting linear address
    output        cpu_dbg_page_fault,
```

but at the machine top level they are connected only to wires that **nothing reads** — they are
not in any telemetry record and not in the debug view. (The telemetry record that exists carries
`CS` and `EIP` but no fault address.) Surfacing `pf_addr`/`pf_code` in that record — the same way
the SDRAM counters were added — would make a capture name the **faulting linear address**. That
is the datum the guest's own printout omits, and it is what separates "a corrupted pointer"
(core bug) from "a legitimately-unmapped access the extender refused" (BIOS/DPMI-emulation or
guest bug).

## 8. Proven vs inferred — read this before acting

**Proven, and re-runnable from this document alone:**

- The arbitration's output values in §4.2, on the core's real RTL, with the CPU's own view masks.
- The producer order, the view masks and the priority mux in §3 — quoted verbatim.
- The fault signature in §1: fixed `CS:EIP`/`EFLAGS`/segment registers, varying data, and the two
  equal register pairs.
- That the supplied trace contains no record outside segment `F760` (§6).

**Inferred, and stated as an assumption:**

- **That `dly` is architecturally *older* than a live token and than `load-wb`.** This rests on
  (a) the module's own comments in §3.1 and (b) the pipeline reading that the retiring
  instruction precedes one that has not retired. **If this premise is false, A7 is not a
  hazard** — challenge it first (§10 step 1). Note the survey itself makes the same reading
  ("which is not the age order").
- **That A7 *causes* the DOOM fault.** The chain is: identical symptom class → the class's
  members were real core bugs → A7 is the only unverified member → A7 is demonstrably
  mis-resolving. Strong, but not a causal proof.

**Not excluded:** the fault could instead be (i) corruption in the machine's memory path
(SDRAM controller / L1 caches / clock-domain crossing) rather than a register-arbitration defect,
or (ii) a bad value the machine's BIOS/DPMI emulation feeds the extender's page-table builder.
Step 2 in §10 is what excludes them.

## 9. Fix direction (not implemented — deliberately)

Re-rank the delay-slot producer to its architectural age (it should be the **oldest**, i.e. lose
to producers 0–3, not beat them). Expect this to be more than an index change:

- **The producer indices are also the bit positions of the three view masks** (§3.3), so a
  renumbering edits the arbitration module, the `vis_*` literals at the CPU level, and every
  bench that hard-codes those masks.
- **`dly` has a legitimate consumer** — it is bypassed into the next instruction's D2 address —
  so the change must be checked against the delay-slot path, not only against the views. The
  core's bench case 7 (§4.3) pins "dly wins" and must be **re-derived**, not merely renumbered.
- Any change to the vendored core carries the machine project's own patch discipline: a marked
  `LOCAL PATCH` block plus a numbered entry in its patch-map document, held together by a static
  checker. If operating outside that project, keep the change minimal, separately revertable,
  and clearly attributed.

## 10. Work plan

Ordered cheapest-first; steps 1 and 2 are independent.

1. **Challenge the premise in §8.** From the core's pipeline, confirm which instruction's write
   `dly_gpr_we` carries, and whether it can ever be *younger* than a live token or a write-back
   (look at where `dly_gpr_we_pre_r` / `dly_gpr_sel_pre_r` are loaded and at the RNI-delay and
   pipeline-advance rules). **If it cannot, A7 is not a hazard and this branch closes.**
2. **Capture the faulting instruction.** Add a page-fault term to the trace trigger that fires
   on a *repeating* fault, and/or surface the latched `pf_addr`/`pf_code` in the telemetry
   record (§7). This is the only step that can promote the hypothesis to a proof, and it also
   excludes the §8 alternatives.
3. **Write A7's directed bench** as a permanent fail-first case — a standalone bench in the
   machine project's bench suite, *not* by editing the vendored core's bench (which pins the
   current behaviour). It must fail on the current tree and pass after the fix.
4. **Only then** re-rank (§9), and re-fit. The machine project's core contract is the
   protected-mode suite (`147/147` at the time of writing), Dhrystone
   `253183 cycles / 121837 instructions / CPI 2.078`, and the boot golden `CYCLES used=930530`.

**Do not** narrow the fault to A7 by inspection alone: without step 2 the other hypotheses in §8
remain live, and the whole point of the fixed `CS:EIP` is that it tells us *where* the bad value
is used, not *where* it was corrupted.

## 11. Appendix — provenance

- Core: z486, upstream `doublej472/z486`, pinned at commit `7065221` (2026-10-04). The class
  history in §5 is the core's own `docs/hazard-survey.md`; the five fixed protected-mode defects
  that landed with the same pin are in its `docs/fix-research.md`.
- The earlier fixed DOOM defects were ported from a sibling z486 port (`Zet98_486_MiSTer`),
  which is where A8's provenance line points.
- Machine: PC-9821 core for MiSTer; the ROM pack and the DOOM media are the owner's and are not
  redistributed.
