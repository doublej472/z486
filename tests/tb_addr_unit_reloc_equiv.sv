`timescale 1ns/1ps

// Cycle-exact equivalence (characterization) bench for the address_unit
// relocation cone: every relocation output and capture must match a golden
// computed in independent arithmetic, with the documented 16-bit offset wraps.

`default_nettype none

module tb_addr_unit_reloc_equiv;
  import z486_pkg::*;

  reg clk = 0;
  always #5 clk = ~clk;
  reg reset_n = 0;
  reg [31:0] cyc = 0;
  always @(posedge clk) cyc <= cyc + 32'd1;

  // ==== DUT ====
  // The address_unit port shape (the harness around the DUT below).
  dec_entry_t instr_i;
  ea_dec_t    d2_ea_i;

  reg         instr_issue = 0;
  reg         d2_start = 0;
  reg         split_ea_prepare = 0;
  reg         split_ea_use = 0;
  reg  [2:0]  split_ea_adjust = 0;
  reg  [31:0] displacement = 0;
  reg  [31:0] ea_base_value = 0;
  reg  [31:0] ea_index_value = 0;
  reg         branch_relative = 0;
  reg  [31:0] branch_target_eip = 0;
  reg  [31:0] forwarded_esp = 0;
  reg         ss_stack32 = 0;
  reg  [31:0] issue_seg_base = 0;
  reg         issue_eff_mask = 0;

  reg         exec = 0;
  reg         exec_addr32 = 0;
  reg  [5:0]  alu_source = 0;
  reg  [8:0]  ind_ctrl = 0;
  reg  [31:0] source_value = 0;
  reg  [31:0] alu_value = 0;
  reg  [31:0] alu_value_hold = 0;
  reg         instr_jcc = 0;
  reg         pe = 0;
  reg         is_dword = 0;
  reg         descsw_mode = 0;
  reg         cs_stack32 = 0;

  reg  [3:0]  seg_cmd = 0;
  reg  [3:0]  seg_sel = 0;
  reg  [31:0] seg_base_pending = 0;
  reg         eff_mask_pending = 0;
  reg  [31:0] lar_result = 0;
  reg  [31:0] llim_result = 0;
  reg  [31:0] lbas_result = 0;
  reg  [2:0]  fault_code = 0;
  reg  [31:0] fault_addr = 0;
  reg  [31:0] cr3 = 0;

  gpr_ref_t ea_base_o, ea_index_o;
  wire [31:0] ind, ind_delta, ind_linear;
  wire        ind_linear_valid;
  wire [31:0] ea, issue_ea, issue_linear;
  wire [31:0] ind_linear_next;
  wire [1:0]  issue_linear_low;

  address_unit dut (
    .clk(clk), .reset_n(reset_n),
    .instr_issue(instr_issue), .instr(instr_i),
    .d2_start(d2_start), .d2_ea(d2_ea_i),
    .split_ea_prepare(split_ea_prepare), .split_ea_use(split_ea_use),
    .split_ea_adjust(split_ea_adjust), .displacement(displacement),
    .ea_base(ea_base_o), .ea_index(ea_index_o),
    .ea_base_value(ea_base_value), .ea_index_value(ea_index_value),
    .branch_relative(branch_relative), .branch_target_eip(branch_target_eip),
    .forwarded_esp(forwarded_esp), .ss_stack32(ss_stack32),
    .issue_seg_base(issue_seg_base), .issue_eff_mask(issue_eff_mask),
    .exec(exec), .exec_addr32(exec_addr32), .alu_source(alu_source),
    .ind_ctrl(ind_ctrl), .source_value(source_value), .alu_value(alu_value),
    .alu_value_hold(alu_value_hold), .jcc_word(instr_jcc), .pe(pe),
    .is_dword(is_dword), .descsw_mode(descsw_mode), .cs_stack32(cs_stack32),
    .seg_cmd(seg_cmd), .seg_sel(seg_sel),
    .seg_base_pending(seg_base_pending), .eff_mask_pending(eff_mask_pending),
    .lar_result(lar_result), .llim_result(llim_result), .lbas_result(lbas_result),
    .fault_code(fault_code), .fault_addr(fault_addr), .cr3(cr3),
    .ind(ind), .ind_delta(ind_delta), .ind_linear(ind_linear),
    .ind_linear_valid(ind_linear_valid), .ea(ea),
    .issue_ea(issue_ea), .issue_linear(issue_linear),
    .issue_mem_linear(),
    .issue_linear_low(issue_linear_low)
  );

  // ==== golden shadow: the documented next-state, in independent arithmetic ====
  reg        g_base_valid = 0, g_index_valid = 0, g_s2b = 0, g_is16 = 0;
  reg [1:0]  g_scale = 0;
  reg [31:0] g_partial = 0;
  reg [31:0] g_ind_delta = 32'd4;
  reg [31:0] g_issue_ind = 0, g_issue_linear_r = 0;
  reg [31:0] g_exec_ind = 0, g_exec_linear_r = 0;
  reg        g_ind_owner = 0, g_linear_owner = 0;

  integer errors = 0;
  integer checks = 0;

  // IND op / dest-class encodings (documented microcode control encoding).
  localparam [3:0] INDOP_PLUS_ALU  = 4'd1;
  localparam [3:0] INDOP_ALU2      = 4'd2;
  localparam [3:0] INDOP_SRC       = 4'd3;
  localparam [3:0] INDOP_PLUS      = 4'd4;
  localparam [3:0] INDOP_IN_PLUS_D = 4'd5;
  localparam [3:0] INDOP_LAR       = 4'd6;
  localparam [3:0] INDOP_LLIM      = 4'd7;
  localparam [3:0] INDOP_LBAS      = 4'd8;
  localparam [3:0] INDOP_LPCR      = 4'd9;
  localparam [2:0] INDDEST_DESSTK  = 3'd1;
  localparam [2:0] INDDEST_DESCOD  = 3'd2;
  localparam [2:0] INDDEST_DESSEG  = 3'd3;
  localparam [2:0] INDDEST_PFERRC  = 3'd4;
  localparam [2:0] INDDEST_LATTTF  = 3'd5;
  localparam [2:0] INDDEST_PDBR    = 3'd6;

  // ==== CHECKS ====
  task automatic fail(input string what, input [31:0] got, input [31:0] want);
    begin
      errors = errors + 1;
      $display("FAIL [relocation-identity] %s at cyc=%0d got=%08x want=%08x",
               what, cyc, got, want);
      if (errors > 16) begin
        $display("TB_ADDR_UNIT_RELOC_EQUIV: FAIL (too many mismatches)");
        $fatal(1, "relocation identity broken");
      end
    end
  endtask

  // ---- the documented EA recipe (base + index<<scale + disp; s2b scales base) ----
  wire [31:0] gt_base_term =
      !g_s2b    ? ea_base_value :
      g_scale==2'd0 ? ea_base_value :
      g_scale==2'd1 ? (ea_base_value << 1) :
      g_scale==2'd2 ? (ea_base_value << 2) : (ea_base_value << 3);
  wire [31:0] gt_index_term =
      g_s2b     ? 32'd0 :
      g_scale==2'd0 ? ea_index_value :
      g_scale==2'd1 ? (ea_index_value << 1) :
      g_scale==2'd2 ? (ea_index_value << 2) : (ea_index_value << 3);

  wire [31:0] g_now_a = split_ea_use ? g_partial :
                        (g_base_valid ? gt_base_term : gt_index_term);
  wire [31:0] g_now_b = split_ea_use ? displacement :
                        ((g_base_valid && g_index_valid && !g_s2b)
                             ? gt_index_term : displacement);
  wire [31:0] g_now_offset = g_now_a + g_now_b;
  wire [31:0] g_now_ea = g_is16 ? {16'd0, g_now_offset[15:0]} : g_now_offset;
  // 16-bit mask zext-wraps the offset before the base add.
  wire [31:0] g_now_linear = (g_is16 || !issue_eff_mask)
                           ? (issue_seg_base + {16'd0, g_now_offset[15:0]})
                           : (issue_seg_base + g_now_offset);
  wire [1:0]  g_now_low = g_now_a[1:0] + g_now_b[1:0] + issue_seg_base[1:0];

  // Documented relocation of an arbitrary offset (issue captures).
  function automatic [31:0] relocate_gold(input [31:0] offset, input masked);
    relocate_gold = issue_seg_base + (masked ? {16'd0, offset[15:0]} : offset);
  endfunction

  // ---- stimulus generation (deterministic xorshift) ----
  reg [31:0] rng = 32'h1234_5678;
  function automatic [31:0] rnd;
    begin
      rng = rng ^ (rng << 13);
      rng = rng ^ (rng >> 17);
      rng = rng ^ (rng << 5);
      rnd = rng;
    end
  endfunction

  localparam integer DIRECTED = 44;

  // Wrap-heavy operands: the 16-bit wraps the cut must not change.
  function automatic [31:0] wrap_operand(input integer sel);
    case (sel % 11)
      0: wrap_operand = 32'h0000_ffff;
      1: wrap_operand = 32'h0000_0002;
      2: wrap_operand = 32'h0000_fffe;
      3: wrap_operand = 32'hffff_ffff;
      4: wrap_operand = 32'h0001_0000;
      5: wrap_operand = 32'h0000_0001;
      6: wrap_operand = 32'h8000_0000;
      7: wrap_operand = 32'h7fff_ffff;
      8: wrap_operand = 32'h0000_1000;
      9: wrap_operand = 32'hffff_f000;
      default: wrap_operand = 32'h0000_fffd;
    endcase
  endfunction

  task automatic drive_quiet;
    begin
      instr_issue = 0; d2_start = 0; split_ea_prepare = 0; split_ea_use = 0;
      exec = 0;
    end
  endtask

  // One stimulus cycle. Issue and exec are kept mutually exclusive (blind (2)).
  task automatic drive_cycle(input integer mode);
    reg [31:0] r0, r1, r2;
    integer s0, s1, s2;
    reg [2:0] cls;
    begin
      drive_quiet();
      r0 = rnd(); r1 = rnd(); r2 = rnd();
      if (mode < DIRECTED) begin
        s0 = (mode * 7 + 1) % 11;
        s1 = (mode * 5 + 3) % 11;
        s2 = (mode * 3 + 2) % 11;
      end else begin
        s0 = r0[19:16];
        s1 = r0[23:20];
        s2 = r0[27:24];
      end
      cls = mode < DIRECTED ? mode[2:0] : r1[18:16];

      case (mode < DIRECTED ? mode % 4 : r1 % 6)
        0: begin
          // modrm D2 issue (covers linear32/linear16 and the EA forms)
          d2_start = 1;
          d2_ea_i.base_sel  = r0[0] ? (8'h01 << r0[5:3]) : 8'h00;
          d2_ea_i.index_sel = r0[1] ? (8'h01 << r0[8:6]) : 8'h00;
          d2_ea_i.scale     = s0[1:0];
          d2_ea_i.disp      = wrap_operand(s2);
          d2_ea_i.is16      = mode < DIRECTED ? s0[2] : r0[2];
          d2_ea_i.s2b       = mode < DIRECTED ? s1[2] : r0[3];
          ea_base_value  = wrap_operand(s1);
          ea_index_value = wrap_operand(s2);
          displacement   = wrap_operand(s0);
          issue_seg_base = wrap_operand(s2);
          issue_eff_mask = mode < DIRECTED ? s1[3] : r0[4];
          instr_i = '0;
          instr_i.has_modrm = 1'b1;
          instr_i.data32 = r0[5];
          instr_i.addr32 = r0[6];
          // half the directed cases settle the recipe one cycle early
          if (!(mode < DIRECTED ? s2[2] : r0[7]))
            instr_issue = 1;
        end
        1: begin
          // stack pop (stack_dir=1): relocate(esp) with the 16-bit SS wrap
          forwarded_esp = wrap_operand(s0);
          ss_stack32    = mode < DIRECTED ? s0[1] : r0[8];
          issue_seg_base = wrap_operand(s1);
          issue_eff_mask = mode < DIRECTED ? s1[1] : r0[9];
          instr_issue = 1;
          instr_i = '0;
          instr_i.stack_op = 1'b1;
          instr_i.stack_dir = 1'b1;
          instr_i.data32 = mode < DIRECTED ? s1[2] : r0[10];
        end
        2: begin
          // stack push (stack_dir=0): fused (esp - 2/4) then relocate
          forwarded_esp = wrap_operand(s0);
          ss_stack32    = mode < DIRECTED ? s0[1] : r0[8];
          issue_seg_base = wrap_operand(s2);
          issue_eff_mask = mode < DIRECTED ? s1[1] : r0[9];
          instr_issue = 1;
          instr_i = '0;
          instr_i.stack_op = 1'b1;
          instr_i.stack_dir = 1'b0;
          instr_i.data32 = mode < DIRECTED ? s1[2] : r0[10];
        end
        3: begin
          // moffs issue
          instr_issue = 1;
          instr_i = '0;
          instr_i.has_moffs = 1'b1;
          instr_i.addr32 = mode < DIRECTED ? s0[0] : r0[11];
          instr_i.immediate = wrap_operand(s1);
          issue_seg_base = wrap_operand(s2);
          issue_eff_mask = mode < DIRECTED ? s1[1] : r0[12];
        end
        4: begin
          // split-EA: prepare the partial sum (recipe + partial land together)
          d2_start = 1;
          d2_ea_i.base_sel  = r0[0] ? (8'h01 << r0[5:3]) : 8'h00;
          d2_ea_i.index_sel = r0[1] ? (8'h01 << r0[8:6]) : 8'h00;
          d2_ea_i.scale     = s0[1:0];
          d2_ea_i.disp      = wrap_operand(s2);
          d2_ea_i.is16      = r0[2];
          d2_ea_i.s2b       = r0[3];
          ea_base_value  = wrap_operand(s1);
          ea_index_value = wrap_operand(s2);
          split_ea_prepare = 1;
          split_ea_adjust  = s0[2:0];
          issue_seg_base = wrap_operand(s0);
          issue_eff_mask = r0[4];
        end
        default: begin
          // exec IND relocation (covers relocate_add2 and relocate_exec)
          exec = 1;
          ind_ctrl = {s2[1], cls};
          source_value  = wrap_operand(s0);
          alu_value     = wrap_operand(s1);
          alu_value_hold = wrap_operand(s2);
          instr_jcc = r0[13];
          alu_source = r0[19:14];
          exec_addr32 = r0[20];
          pe = r0[21];
          is_dword = r0[22];
          descsw_mode = r0[23];
          cs_stack32 = r0[24];
          seg_base_pending = wrap_operand(s2);
          eff_mask_pending = mode < DIRECTED ? s0[1] : r0[25];
          seg_cmd = s2[2] ? SEG_CMD_DESCSW : 4'd0;
          seg_sel = SEG_SS;
          lar_result = r0; llim_result = r1; lbas_result = r2;
          fault_code = r1[2:0]; fault_addr = r1; cr3 = r2;
        end
      endcase

      // occasionally finish a split-EA in its use phase
      if (mode >= DIRECTED && (r2[3:0] == 4'hf)) begin
        split_ea_use = 1;
        displacement = wrap_operand(s2);
      end
    end
  endtask

  // ==== checks ====
  // Combinational relocation outputs every cycle (golden wires above).
  always @(negedge clk) begin
    #1;
    if (reset_n) begin
      checks = checks + 1;
      if (issue_ea !== g_now_ea)
        fail("issue_ea", issue_ea, g_now_ea);
      if (issue_linear !== g_now_linear)
        fail("issue_linear", issue_linear, g_now_linear);
      if (issue_linear_low !== g_now_low)
        fail("issue_linear_low", {30'd0, issue_linear_low}, {30'd0, g_now_low});
    end
  end

  // Registered captures + shadow advance (post-edge vs pre-edge inputs).
  reg [31:0] stack_off, next_ind, op1, op2, exec_src, exec_lin;
  reg        mask16_i, three_term, lin_write, exec_ind_write;
  always @(posedge clk) begin
    #1;
    if (!reset_n) begin
      g_partial = 0; g_ind_delta = 32'd4;
      g_issue_ind = 0; g_issue_linear_r = 0;
      g_exec_ind = 0; g_exec_linear_r = 0;
      g_ind_owner = 0; g_linear_owner = 0;
      g_base_valid = 0; g_index_valid = 0; g_s2b = 0; g_is16 = 0; g_scale = 0;
    end else begin
      // ---- next-state golden from the PRE-edge inputs and shadows ----
      stack_off = 0; next_ind = 0; exec_src = 0; exec_lin = 0;
      mask16_i = !eff_mask_pending;
      three_term = 0;
      lin_write = (seg_cmd == SEG_CMD_DESCSW) ||
                  ((ind_ctrl[8]) && (seg_sel == SEG_SS));
      exec_ind_write = 1;

      // split-EA partial capture (uses the PRE-edge recipe registers)
      if (split_ea_prepare)
        g_partial = gt_base_term + gt_index_term + {29'd0, split_ea_adjust};

      // D2 issue captures, before the d2_start shadow advance below.
      if (instr_issue) begin
        g_ind_delta = !instr_i.stack_op ? 32'd2 :
                      !instr_i.stack_dir ? (instr_i.data32 ? -32'd4 : -32'd2) :
                                           (instr_i.data32 ? 32'd4 : 32'd2);
        if (instr_i.stack_op && instr_i.stack_dir) begin
          stack_off = ss_stack32 ? forwarded_esp : {16'd0, forwarded_esp[15:0]};
          g_issue_ind = stack_off;
          g_issue_linear_r = relocate_gold(stack_off, !issue_eff_mask);
        end else if (instr_i.stack_op && !instr_i.stack_dir) begin
          stack_off = ss_stack32
                    ? (forwarded_esp - (instr_i.data32 ? 32'd4 : 32'd2))
                    : {16'd0, forwarded_esp[15:0] -
                               (instr_i.data32 ? 16'd4 : 16'd2)};
          g_issue_ind = stack_off;
          g_issue_linear_r = relocate_gold(stack_off, !issue_eff_mask);
        end else if (instr_i.has_moffs) begin
          stack_off = instr_i.addr32 ? instr_i.immediate
                                     : {16'd0, instr_i.immediate[15:0]};
          g_issue_ind = stack_off;
          // quirk: IND takes the truncated immediate, relocation the full one
          g_issue_linear_r = relocate_gold(instr_i.immediate, !issue_eff_mask);
        end else if (instr_i.has_modrm) begin
          g_issue_ind = g_now_ea;
          g_issue_linear_r = g_now_linear;
        end
        g_ind_owner = 1'b1;
        g_linear_owner = 1'b1;
      end

      if (exec) begin
        exec_src = ind_ctrl[3:0] == INDOP_ALU2 ? alu_value :
                   ind_ctrl[3:0] == INDOP_SRC  ? source_value :
                   (g_ind_owner ? g_issue_ind : g_exec_ind);
        case (ind_ctrl[3:0])
          INDOP_PLUS_ALU: begin
            lin_write = 1'b1;
            op1 = ind_ctrl[4] ? (g_ind_owner ? g_issue_ind : g_exec_ind)
                              : source_value;
            op2 = instr_jcc ? alu_value_hold : alu_value;
            if (ind_ctrl[7:5] == INDDEST_DESSTK)      mask16_i = !pe || !ss_stack32;
            else if (ind_ctrl[7:5] == INDDEST_DESCOD) mask16_i = !is_dword;
            else if (ind_ctrl[7:5] == INDDEST_DESSEG) mask16_i = !exec_addr32;
            next_ind = op1 + op2;
            if (mask16_i && (ind_ctrl[7:5] == INDDEST_DESSTK ||
                             ind_ctrl[7:5] == INDDEST_DESCOD ||
                             ind_ctrl[7:5] == INDDEST_DESSEG))
              next_ind = {16'd0, next_ind[15:0]};
            three_term = 1;
            exec_lin = seg_base_pending +
                       (mask16_i ? {16'd0, op1[15:0] + op2[15:0]}
                                 : (op1 + op2));
            if (alu_source != ALUSRC_ZERO) g_ind_delta = op2;
            g_ind_owner = 1'b0;
          end
          INDOP_ALU2: begin
            lin_write = 1'b1;
            next_ind = alu_value;
            exec_lin = seg_base_pending +
                       (eff_mask_pending ? alu_value : {16'd0, alu_value[15:0]});
            g_ind_owner = 1'b0;
          end
          INDOP_SRC: begin
            lin_write = 1'b1;
            next_ind = source_value;
            if (ind_ctrl[7:5] == INDDEST_DESSTK && (!pe || !ss_stack32))
              next_ind = {16'd0, next_ind[15:0]};
            else if (ind_ctrl[7:5] == INDDEST_DESCOD && !is_dword)
              next_ind = {16'd0, next_ind[15:0]};
            if (ind_ctrl[7:5] == INDDEST_DESSTK && (!pe || !ss_stack32))
              exec_src = {16'd0, source_value[15:0]};
            else if (ind_ctrl[7:5] == INDDEST_DESCOD && !is_dword)
              exec_src = {16'd0, source_value[15:0]};
            exec_lin = seg_base_pending +
                       (eff_mask_pending ? exec_src : {16'd0, exec_src[15:0]});
            g_ind_owner = 1'b0;
          end
          INDOP_PLUS: begin
            lin_write = 1'b1;
            op1 = g_ind_owner ? g_issue_ind : g_exec_ind;
            next_ind = op1 + alu_value;
            if (!pe && !exec_addr32) next_ind = {16'd0, next_ind[15:0]};
            three_term = 1;
            exec_lin = seg_base_pending +
                       (mask16_i ? {16'd0, op1[15:0] + alu_value[15:0]}
                                 : (op1 + alu_value));
            if (alu_source != ALUSRC_ZERO) g_ind_delta = alu_value;
            g_ind_owner = 1'b0;
          end
          INDOP_IN_PLUS_D: begin
            lin_write = 1'b1;
            op1 = g_ind_owner ? g_issue_ind : g_exec_ind;
            next_ind = op1 + g_ind_delta;
            if (!pe ? !exec_addr32
                    : !(descsw_mode ? cs_stack32 : ss_stack32))
              next_ind = {16'd0, next_ind[15:0]};
            three_term = 1;
            exec_lin = seg_base_pending +
                       (mask16_i ? {16'd0, op1[15:0] + g_ind_delta[15:0]}
                                 : (op1 + g_ind_delta));
            g_ind_owner = 1'b0;
          end
          INDOP_LAR:  begin next_ind = lar_result;  g_ind_owner = 1'b0; end
          INDOP_LLIM: begin next_ind = llim_result; g_ind_owner = 1'b0; end
          INDOP_LBAS: begin next_ind = lbas_result; g_ind_owner = 1'b0; end
          INDOP_LPCR: begin
            case (ind_ctrl[7:5])
              INDDEST_PFERRC: begin next_ind = {29'd0, fault_code}; g_ind_owner = 1'b0; end
              INDDEST_LATTTF: begin next_ind = fault_addr; g_ind_owner = 1'b0; end
              INDDEST_PDBR:   begin next_ind = cr3; g_ind_owner = 1'b0; end
              default: exec_ind_write = 0;
            endcase
          end
          default: exec_ind_write = 0;
        endcase
        if (exec_ind_write) g_exec_ind = next_ind;
        if (lin_write) begin
          if (three_term) g_exec_linear_r = exec_lin;
          else g_exec_linear_r = seg_base_pending +
                 (eff_mask_pending ? exec_src : {16'd0, exec_src[15:0]});
          g_linear_owner = 1'b0;
        end
      end

      // d2_start advances the recipe shadow AFTER the captures above
      if (d2_start) begin
        g_base_valid  = |d2_ea_i.base_sel;
        g_index_valid = |d2_ea_i.index_sel;
        g_scale       = d2_ea_i.scale;
        g_is16        = d2_ea_i.is16;
        g_s2b         = d2_ea_i.s2b;
      end

      // ---- compare the post-edge outputs against the golden captures ----
      checks = checks + 1;
      if (ind !== (g_ind_owner ? g_issue_ind : g_exec_ind))
        fail("ind", ind, g_ind_owner ? g_issue_ind : g_exec_ind);
      if (ind_linear !== (g_linear_owner ? g_issue_linear_r : g_exec_linear_r))
        fail("ind_linear", ind_linear,
             g_linear_owner ? g_issue_linear_r : g_exec_linear_r);
      if (ind_delta !== g_ind_delta)
        fail("ind_delta", ind_delta, g_ind_delta);
    end
  end

  // ==== run ====
  integer i;
  initial begin
    instr_i = '0;
    d2_ea_i = '0;
    reset_n = 0;
    repeat (4) @(negedge clk);
    reset_n = 1;
    // directed wrap cases first, then deterministic random mixing
    for (i = 0; i < DIRECTED + 20000; i = i + 1) begin
      @(negedge clk);
      drive_cycle(i);
    end
    @(negedge clk);
    drive_quiet();
    @(negedge clk);
    // ==== VERDICT ====
    if (errors != 0) begin
      $display("TB_ADDR_UNIT_RELOC_EQUIV: FAIL (%0d mismatches in %0d checks)",
               errors, checks);
      $fatal(1, "relocation identity broken");
    end
    $display("z486_reloc_equiv: %0d checks, %0d cycles", checks, cyc);
    $display("TB_ADDR_UNIT_RELOC_EQUIV: PASS");
    $finish;
  end
endmodule

`default_nettype wire
