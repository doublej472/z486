//
// gpr_write_merge
//
// One canonical arbitration for every register producer that can be in flight
// at the same time.  The commit path and all three forwarding views are built
// from this module's outputs, so a consumer can never see a different winner
// from the one the register file commits.
//
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
//   5 rep-stos     the REP STOS restartable count (COUNTR -> ECX), recorded
//                  once the element store has cleared DLY.
//   6 sigsrc       a SIGSRC recipe commit (MOVZX/MOVSX: SIGMA -> SRCREG) at the
//                  RNI-word cycle.
//   7 esp          an ESP recipe commit (PUSH: post-push SIGMA -> ESP).
//
// Producers 5-7 are the recipe commits.  They are consolidated here so the
// register file applies them from the one canonical age order (their original
// separate write_gpr pulses are gone) and are emitted as pulse_value/
// pulse_wmask for that write.  They are deliberately NOT forwarded: each view
// mask leaves bits 7:5 clear, because a recipe commit is the retiring
// instruction's own write and no younger consumer samples a view for that
// register in its commit cycle.  Forwarding them was tried and is correct, but
// it puts their decode on the EA/ALU forwarding cone and costs slack for no
// correctness gain; see docs/hazard-survey.md.
//
// The merge is byte granular: each byte lane is an independent eight-input
// priority mux that takes the value from the youngest visible producer whose
// lane enable covers that byte, else the register's current byte.  Writing it
// per byte instead of as a chain of whole-word merges keeps the depth at one
// mux per byte, which matters because these values feed the operand-read and
// register-write cones.  Each producer contributes exactly one aligned 32-bit
// value and one 4-bit lane enable; only the enable is compared per register.
//
// A producer is {lane enable, right-aligned value} - exactly what the register
// file's own write_gpr consumes - so the partial-register cases (byte-low /
// byte-high / word / dword, AH vs AL) are one expression here and cannot drift
// from the register file.  A byte producer's encoding is {high_byte, reg[1:0]}:
// the register is dst[1:0] and dst[2] selects AH/AL of that same register.
//
// An M3 ALU result (a loaded operand feeding the shared ALU) is committed like
// any other write-back but must not be forwarded: it is itself derived from
// these views, so forwarding it would close a combinational loop.  Its readers
// are interlocked instead.
//
module gpr_write_merge
    import z486_pkg::*;
(
    // Register value before this edge, 8 x 32 bits.
    input  logic [255:0] cur,

    // Producer 0 (oldest): deferred shift token.
    input  logic         v_shift,
    input  logic [2:0]   dst_shift,
    input  logic [1:0]   size_shift,
    input  logic [31:0]  data_shift,

    // Producer 1: deferred memory (hardwired load) token.
    input  logic         v_mem,
    input  logic [2:0]   dst_mem,
    input  logic [1:0]   mode_mem,      // EA_FWD_BLO / _BHI / _W / _D
    input  logic [31:0]  data_mem,      // OPR_R

    // Producer 2: interrupt-entry ROM writeback slot.
    input  logic         v_rom,
    input  logic [2:0]   dst_rom,
    input  logic [1:0]   size_rom,
    input  logic [31:0]  data_rom,      // OPR_R

    // Producer 3: direct-load write-back.
    input  logic         v_wb,
    input  logic [2:0]   dst_wb,
    input  logic [1:0]   size_wb,
    input  logic         wb_is_alu,     // M3 ALU result: commit only, never forwarded
    input  logic [31:0]  data_wb,

    // Producer 4: delay-slot bypass (views only).
    input  logic         v_dly,
    input  logic [2:0]   dst_dly,
    input  logic [1:0]   mode_dly,
    input  logic [31:0]  data_dly,

    // Producer 5: REP STOS restartable count (COUNTR -> ECX).
    input  logic         v_stos,
    input  logic [1:0]   size_stos,     // 2'd1 word / 2'd2 dword
    input  logic [31:0]  data_stos,

    // Producer 6: SIGSRC recipe commit (SIGMA -> SRCREG).
    input  logic         v_sigsrc,
    input  logic [2:0]   dst_sigsrc,
    input  logic [1:0]   size_sigsrc,   // 2'd1 word / 2'd2 dword
    input  logic [31:0]  data_sigsrc,

    // Producer 7 (youngest): ESP recipe commit (SIGMA -> ESP, always a dword).
    input  logic         v_esp,
    input  logic [31:0]  data_esp,

    // Which producers each consumer observes.  Views differ only in
    // *visibility*, never in order.  `commit` is fixed at {shift, mem, rom, wb}
    // because the delay slot's architectural write is an EX write; the recipe
    // commits are applied by a second merged write (pulse_value/pulse_wmask),
    // and the CPU wiring intentionally leaves them out of all three view masks.
    input  logic [7:0]   vis_ex,
    input  logic [7:0]   vis_ea,
    input  logic [7:0]   vis_cap,

    output logic [255:0] commit_value,
    output logic [255:0] commit_wmask,  // byte lanes the commit actually writes
    output logic [255:0] pulse_value,   // recipe commits, applied after commit
    output logic [255:0] pulse_wmask,   // byte lanes the recipe commits write
    output logic [255:0] ex_value,
    output logic [255:0] ea_value,
    output logic [255:0] cap_value,

    // The capture view for two SELECTED registers. Value-identical to
    // cap_value[sel*32 +: 32], but merged after the register is chosen (one
    // 32-bit merge per reader instead of 256 bits followed by an 8:1 mux), so
    // a consumer that only ever reads one register per port leaves the full
    // cap_value unread and synthesis drops it.
    input  logic [2:0]   cap_sel_a,
    input  logic [2:0]   cap_sel_b,
    output logic [31:0]  cap_a_value,
    output logic [31:0]  cap_b_value
);

localparam logic [7:0] VIS_COMMIT = 8'h0F;   // shift, mem, rom, wb
localparam logic [7:0] VIS_PULSE  = 8'hE0;   // stos, sigsrc, esp

// ---------------------------------------------------------------------------
// Producer lane decoding.  Mirrors the register file's write_gpr exactly.
// ---------------------------------------------------------------------------

// Byte enable for an access of `size` in the lane selected by `high_byte`: a
// byte access to "AH" is byte 1 of the same 32-bit register, a word is both low
// bytes, a dword all four.
function automatic logic [3:0] be_of_size(input logic [1:0] size, input logic high_byte);
    be_of_size = (size == 2'd0) ? (high_byte ? 4'h2 : 4'h1)
               : (size == 2'd1) ? 4'h3
               :                  4'hF;
endfunction

function automatic logic [3:0] be_of_mode(input logic [1:0] mode);
    case (mode)
        EA_FWD_BLO: be_of_mode = 4'h1;
        EA_FWD_BHI: be_of_mode = 4'h2;
        EA_FWD_W:   be_of_mode = 4'h3;
        default:    be_of_mode = 4'hF;
    endcase
endfunction

// A producer's value is right-aligned in its natural width, so move it into the
// lane it owns.  Mirrors write_gpr, including the AH/AL choice.
function automatic logic [31:0] align_of_size(input logic [1:0] size,
                                              input logic high_byte,
                                              input logic [31:0] data);
    align_of_size = (size == 2'd0) ? (high_byte ? {16'h0, data[7:0], 8'h0}
                                                : {24'h0, data[7:0]})
                  : (size == 2'd1) ? {16'h0, data[15:0]}
                  :                  data;
endfunction

function automatic logic [31:0] align_of_mode(input logic [1:0] mode,
                                              input logic [31:0] data);
    case (mode)
        EA_FWD_BLO: align_of_mode = {24'h0, data[7:0]};
        EA_FWD_BHI: align_of_mode = {16'h0, data[7:0], 8'h0};
        EA_FWD_W:   align_of_mode = {16'h0, data[15:0]};
        default:    align_of_mode = data;
    endcase
endfunction

// Destination register of a producer.  A byte producer addresses {high, reg[1:0]}.
function automatic logic [2:0] dst_norm(input int step);
    case (step)
        0: dst_norm = (size_shift == 2'd0) ? {1'b0, dst_shift[1:0]} : dst_shift;
        1: dst_norm = ((mode_mem == EA_FWD_BLO) || (mode_mem == EA_FWD_BHI))
                    ? {1'b0, dst_mem[1:0]} : dst_mem;
        2: dst_norm = (size_rom == 2'd0) ? {1'b0, dst_rom[1:0]} : dst_rom;
        3: dst_norm = (size_wb == 2'd0) ? {1'b0, dst_wb[1:0]} : dst_wb;
        4: dst_norm = ((mode_dly == EA_FWD_BLO) || (mode_dly == EA_FWD_BHI))
                    ? {1'b0, dst_dly[1:0]} : dst_dly;
        // The recipe commits are never byte-sized, so there is no AH/AL remap.
        // ECX is 3'd1 and ESP is 3'd4 in the register-file encoding.
        5: dst_norm = 3'd1;
        6: dst_norm = dst_sigsrc;
        default: dst_norm = 3'd4;
    endcase
endfunction

function automatic logic producer_valid(input int step);
    case (step)
        0: producer_valid = v_shift;
        1: producer_valid = v_mem;
        2: producer_valid = v_rom;
        3: producer_valid = v_wb;
        4: producer_valid = v_dly;
        5: producer_valid = v_stos;
        6: producer_valid = v_sigsrc;
        default: producer_valid = v_esp;
    endcase
endfunction

function automatic logic [3:0] producer_lane(input int step);
    case (step)
        0: producer_lane = be_of_size(size_shift, dst_shift[2]);
        1: producer_lane = be_of_mode(mode_mem);
        2: producer_lane = be_of_size(size_rom, dst_rom[2]);
        3: producer_lane = be_of_size(size_wb, dst_wb[2]);
        4: producer_lane = be_of_mode(mode_dly);
        5: producer_lane = be_of_size(size_stos, 1'b0);
        6: producer_lane = be_of_size(size_sigsrc, 1'b0);
        default: producer_lane = 4'hF;   // ESP commit is always a full dword
    endcase
endfunction

// The producer's contribution, placed in the lane it owns.  An M3 ALU result is
// already placed in its operand's lane by the same rule, because both are
// right-aligned in their operand width.
function automatic logic [31:0] producer_value(input int step);
    case (step)
        0: producer_value = align_of_size(size_shift, dst_shift[2], data_shift);
        1: producer_value = align_of_mode(mode_mem, data_mem);
        2: producer_value = align_of_size(size_rom, dst_rom[2], data_rom);
        3: producer_value = align_of_size(size_wb, dst_wb[2], data_wb);
        4: producer_value = align_of_mode(mode_dly, data_dly);
        5: producer_value = align_of_size(size_stos, 1'b0, data_stos);
        6: producer_value = align_of_size(size_sigsrc, 1'b0, data_sigsrc);
        default: producer_value = data_esp;
    endcase
endfunction

// One aligned value per producer, computed once.  Quartus 17 cannot part-select
// the result of a function call, so the values are named wires.
wire [31:0] pv0 = producer_value(0);
wire [31:0] pv1 = producer_value(1);
wire [31:0] pv2 = producer_value(2);
wire [31:0] pv3 = producer_value(3);
wire [31:0] pv4 = producer_value(4);
wire [31:0] pv5 = producer_value(5);
wire [31:0] pv6 = producer_value(6);
wire [31:0] pv7 = producer_value(7);

// The capture-view merge for one selected register: the same terms in the same
// order as byte_cap below, with the register comparison folded into each hit.
function automatic logic [31:0] cap_select(input logic [2:0] sel);
    logic [3:0] en [8];
    logic [31:0] cv;
    logic [31:0] pvs [8];
    pvs[0] = pv0; pvs[1] = pv1; pvs[2] = pv2; pvs[3] = pv3;
    pvs[4] = pv4; pvs[5] = pv5; pvs[6] = pv6; pvs[7] = pv7;
    for (int k = 0; k < 8; k++)
        en[k] = (dst_norm(k) == sel) ? producer_lane(k) : 4'h0;
    cv = cur[sel*32 +: 32];
    for (int bb = 0; bb < 4; bb++) begin
        // lowest priority first, so a later (younger, higher-priority) hit wins
        for (int k = 0; k < 8; k++) begin
            if (vis_cap[k] && producer_valid(k) && en[k][bb] &&
                !((k == 3) && wb_is_alu))
                cv[bb*8 +: 8] = pvs[k][bb*8 +: 8];
        end
    end
    cap_select = cv;
endfunction

assign cap_a_value = cap_select(cap_sel_a);
assign cap_b_value = cap_select(cap_sel_b);

genvar r, b;
generate
for (r = 0; r < 8; r++) begin : g_reg
    // Lane enable of each producer for this register (0 = another register).
    wire [3:0] en0 = (dst_norm(0) == r[2:0]) ? producer_lane(0) : 4'h0;
    wire [3:0] en1 = (dst_norm(1) == r[2:0]) ? producer_lane(1) : 4'h0;
    wire [3:0] en2 = (dst_norm(2) == r[2:0]) ? producer_lane(2) : 4'h0;
    wire [3:0] en3 = (dst_norm(3) == r[2:0]) ? producer_lane(3) : 4'h0;
    wire [3:0] en4 = (dst_norm(4) == r[2:0]) ? producer_lane(4) : 4'h0;
    wire [3:0] en5 = (dst_norm(5) == r[2:0]) ? producer_lane(5) : 4'h0;
    wire [3:0] en6 = (dst_norm(6) == r[2:0]) ? producer_lane(6) : 4'h0;
    wire [3:0] en7 = (dst_norm(7) == r[2:0]) ? producer_lane(7) : 4'h0;

    for (b = 0; b < 4; b++) begin : g_byte
        // `forwarding` selects the view enable of the write-back: an M3 ALU
        // result is committed but never forwarded.
        wire hit0 = v_shift && en0[b];
        wire hit1 = v_mem   && en1[b];
        wire hit2 = v_rom   && en2[b];
        wire hit3 = v_wb    && en3[b];
        wire hit4 = v_dly   && en4[b];
        wire hit5 = v_stos  && en5[b];
        wire hit6 = v_sigsrc && en6[b];
        wire hit7 = v_esp   && en7[b];

        wire hitv3 = hit3 && !wb_is_alu;

        // commit_value/pulse_value are defined ONLY in the lanes their wmask sets: the one
        // consumer (data_unit's commit_merged) writes a byte lane only under its mask bit, and
        // the mask is exactly the OR of the same hits, so the register's own byte (`cur`) can
        // never be the selected arm of a written lane. Dropping that arm leaves the lowest-
        // priority producer as the default, which is value-exact wherever the mask is set and
        // removes one 8-bit input from 2 x 256 merge bits.
        always_comb begin : byte_commit
            commit_value[r*32 + b*8 +: 8] = (hit3 && VIS_COMMIT[3]) ? pv3[b*8 +: 8] :
                                            (hit2 && VIS_COMMIT[2]) ? pv2[b*8 +: 8] :
                                            (hit1 && VIS_COMMIT[1]) ? pv1[b*8 +: 8] :
                                                                      pv0[b*8 +: 8];
            commit_wmask[r*32 + b*8 +: 8] = {8{(hit0 && VIS_COMMIT[0]) ||
                                               (hit1 && VIS_COMMIT[1]) ||
                                               (hit2 && VIS_COMMIT[2]) ||
                                               (hit3 && VIS_COMMIT[3])}};
            // The recipe commits are a second merged write, applied after the
            // deferred producers and after the ordinary EX writes, which keeps
            // the original assignment order of the register file.
            pulse_value[r*32 + b*8 +: 8]   = (hit7 && VIS_PULSE[7]) ? pv7[b*8 +: 8] :
                                            (hit6 && VIS_PULSE[6]) ? pv6[b*8 +: 8] :
                                                                     pv5[b*8 +: 8];
            pulse_wmask[r*32 + b*8 +: 8]   = {8{((hit5 && VIS_PULSE[5]) ||
                                                 (hit6 && VIS_PULSE[6]) ||
                                                 (hit7 && VIS_PULSE[7]))}};
        end

        // Views: identical terms, identical order, only visibility differs.
        always_comb begin : byte_ex
            ex_value[r*32 + b*8 +: 8] = (hit7 && vis_ex[7])    ? pv7[b*8 +: 8] :
                                        (hit6 && vis_ex[6])    ? pv6[b*8 +: 8] :
                                        (hit5 && vis_ex[5])    ? pv5[b*8 +: 8] :
                                        (hit4 && vis_ex[4])    ? pv4[b*8 +: 8] :
                                        (hitv3 && vis_ex[3])   ? pv3[b*8 +: 8] :
                                        (hit2 && vis_ex[2])    ? pv2[b*8 +: 8] :
                                        (hit1 && vis_ex[1])    ? pv1[b*8 +: 8] :
                                        (hit0 && vis_ex[0])    ? pv0[b*8 +: 8] :
                                                                 cur[r*32 + b*8 +: 8];
        end

        always_comb begin : byte_ea
            ea_value[r*32 + b*8 +: 8]  = (hit7 && vis_ea[7])   ? pv7[b*8 +: 8] :
                                         (hit6 && vis_ea[6])   ? pv6[b*8 +: 8] :
                                         (hit5 && vis_ea[5])   ? pv5[b*8 +: 8] :
                                         (hit4 && vis_ea[4])   ? pv4[b*8 +: 8] :
                                         (hitv3 && vis_ea[3])  ? pv3[b*8 +: 8] :
                                         (hit2 && vis_ea[2])   ? pv2[b*8 +: 8] :
                                         (hit1 && vis_ea[1])   ? pv1[b*8 +: 8] :
                                         (hit0 && vis_ea[0])   ? pv0[b*8 +: 8] :
                                                                 cur[r*32 + b*8 +: 8];
        end

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
    end
end
endgenerate

// synthesis translate_off
// Independent equivalence guard: the same producers in the same order, but
// merged as whole-word byte-mask chains instead of per-byte priority, so a
// change to one path (or to the age order) fails the suite instead of a game.
function automatic logic hit_of(input int step, input int rr, input int bb,
                                input logic forwarding);
    logic [3:0] en;
    logic       dst_ok;
    dst_ok = (dst_norm(step) == rr[2:0]);
    en     = dst_ok ? producer_lane(step) : 4'h0;
    hit_of = producer_valid(step) && en[bb] &&
             !(forwarding && (step == 3) && wb_is_alu);
endfunction

function automatic logic [31:0] ref_chain(input int rr, input logic [7:0] vis,
                                          input logic forwarding);
    logic [31:0] acc, be, d32;
    acc = cur[rr*32 +: 32];
    for (int step = 0; step < 8; step++) begin
        be  = 32'd0;
        d32 = 32'd0;
        for (int bb = 0; bb < 4; bb++) begin
            be[8*bb +: 8]  = {8{hit_of(step, rr, bb, forwarding)}};
            d32[8*bb +: 8] = producer_value(step)[bb*8 +: 8];
        end
        if (vis[step])
            acc = (acc & ~be) | (d32 & be);
    end
    ref_chain = acc;
endfunction

always_comb begin : merge_equiv_fuse
    for (int rr = 0; rr < 8; rr++) begin
        // commit/pulse are compared in their written lanes only (see byte_commit), and the
        // mask itself is checked against the chain's own write set.
        if ((commit_value[rr*32 +: 32] & commit_wmask[rr*32 +: 32]) !==
            (ref_chain(rr, VIS_COMMIT, 1'b0) & commit_wmask[rr*32 +: 32]))
            $fatal(1, "GPR MERGE COMMIT MISMATCH reg %0d: %08x vs chain %08x",
                   rr, commit_value[rr*32 +: 32], ref_chain(rr, VIS_COMMIT, 1'b0));
        if ((pulse_value[rr*32 +: 32] & pulse_wmask[rr*32 +: 32]) !==
            (ref_chain(rr, VIS_PULSE, 1'b0) & pulse_wmask[rr*32 +: 32]))
            $fatal(1, "GPR MERGE PULSE MISMATCH reg %0d: %08x vs chain %08x",
                   rr, pulse_value[rr*32 +: 32], ref_chain(rr, VIS_PULSE, 1'b0));
        if ((ref_chain(rr, VIS_COMMIT, 1'b0) ^ cur[rr*32 +: 32]) & ~commit_wmask[rr*32 +: 32])
            $fatal(1, "GPR MERGE COMMIT MASK MISMATCH reg %0d", rr);
        if ((ref_chain(rr, VIS_PULSE, 1'b0) ^ cur[rr*32 +: 32]) & ~pulse_wmask[rr*32 +: 32])
            $fatal(1, "GPR MERGE PULSE MASK MISMATCH reg %0d", rr);
        if (ex_value[rr*32 +: 32] !== ref_chain(rr, vis_ex, 1'b1))
            $fatal(1, "GPR MERGE EX VIEW MISMATCH reg %0d: %08x vs chain %08x",
                   rr, ex_value[rr*32 +: 32], ref_chain(rr, vis_ex, 1'b1));
        if (ea_value[rr*32 +: 32] !== ref_chain(rr, vis_ea, 1'b1))
            $fatal(1, "GPR MERGE EA VIEW MISMATCH reg %0d: %08x vs chain %08x",
                   rr, ea_value[rr*32 +: 32], ref_chain(rr, vis_ea, 1'b1));
        if ((rr == int'(cap_sel_a)) && (cap_a_value !== ref_chain(rr, vis_cap, 1'b1)))
            $fatal(1, "GPR MERGE SELECTED CAPTURE A MISMATCH reg %0d: %08x vs chain %08x",
                   rr, cap_a_value, ref_chain(rr, vis_cap, 1'b1));
        if ((rr == int'(cap_sel_b)) && (cap_b_value !== ref_chain(rr, vis_cap, 1'b1)))
            $fatal(1, "GPR MERGE SELECTED CAPTURE B MISMATCH reg %0d: %08x vs chain %08x",
                   rr, cap_b_value, ref_chain(rr, vis_cap, 1'b1));
        if (cap_value[rr*32 +: 32] !== ref_chain(rr, vis_cap, 1'b1))
            $fatal(1, "GPR MERGE CAPTURE VIEW MISMATCH reg %0d: %08x vs chain %08x",
                   rr, cap_value[rr*32 +: 32], ref_chain(rr, vis_cap, 1'b1));
    end
end

// Note: the recipe commits are intentionally absent from vis_ex/vis_ea/vis_cap
// in the CPU wiring.  A recipe commit is the retiring instruction's own write,
// and no younger consumer samples a view for that register in the commit cycle,
// so it is applied only through pulse_value/pulse_wmask (the register-file
// write) and not forwarded.  See docs/hazard-survey.md for the fit rationale.

// A producer a consumer can observe must also be committed: otherwise a reader
// could see a value the register file never receives.  The delay-slot bypass is
// the one exception, because its architectural write is the instruction's own
// EX write.  The recipe commits are committed by the separate pulse_value/
// pulse_wmask write and are intentionally not observable in the views.
initial begin : merge_policy_fuse
    if ((vis_ex | vis_ea | vis_cap) & ~(VIS_COMMIT | VIS_PULSE | 8'h10))
        $fatal(1, "GPR MERGE POLICY: a visible producer is not committed");
    if (!(vis_ex[3] && vis_ea[3] && vis_cap[3]))
        $fatal(1, "GPR MERGE POLICY: the write-back must be visible in every view");
end
// synthesis translate_on

endmodule
