// check-equiv: tempinduct
// ucode_rom.sv q_shift_use_captured_r against the shifter's former
// use_captured_source = is_shift2 || (aluop == SHIFT && source_class == 3),
// whose three inputs are q_is_shift2_r, q_r[17:11] and
// q_shift_source_class_r - all loaded from the same q_mem on the same q_ce,
// none reset, all powering up 0.  Sequential: proved by induction from the
// all-zero power-up state.  MUTANT=1 loads the predecoded flop without q_ce
// and must be refuted.
module shift_use_captured #(parameter MUTANT = 0)
  (input clk, input q_ce, input [6:0] q_aluop, input [5:0] q_src, output mismatch);
  function automatic [3:0] shift_source_predecode(input [5:0] s);   // ucode_rom.sv
    case (s)
      6'h1E: shift_source_predecode = 4'd1;   // SRC_SIGMA
      6'h3D: shift_source_predecode = 4'd2;   // SRC_DSTREG
      6'h3E: shift_source_predecode = 4'd3;   // SRC_SRCREG
      6'h1F: shift_source_predecode = 4'd4;   // SRC_IMM
      6'h0B: shift_source_predecode = 4'd5;   // SRC_TMPB
      6'h0C: shift_source_predecode = 4'd6;   // SRC_TMPC
      6'h0D: shift_source_predecode = 4'd7;   // SRC_TMPD
      6'h0E: shift_source_predecode = 4'd8;   // SRC_TMPE
      6'h2D: shift_source_predecode = 4'd9;   // SRC_OPR_R
      6'h14: shift_source_predecode = 4'd10;  // SRC_COUNTR
      6'h3F: shift_source_predecode = 4'd11;  // SRC_NEG1
      default: shift_source_predecode = 4'd0;
    endcase
  endfunction
  localparam [6:0] ALUJMP_SHIFT = 7'h10, ALUJMP_SHIFT2 = 7'h12;
  reg [6:0] aluop_r = 0; reg [3:0] class_r = 0; reg is_shift2_r = 0; reg use_r = 0;
  wire use_d = (q_aluop == ALUJMP_SHIFT2) ||
               ((q_aluop == ALUJMP_SHIFT) && (shift_source_predecode(q_src) == 4'd3));
  always @(posedge clk) begin
    if (q_ce) begin
      aluop_r <= q_aluop;
      class_r <= shift_source_predecode(q_src);
      is_shift2_r <= (q_aluop == ALUJMP_SHIFT2);
    end
    if (q_ce || MUTANT) use_r <= use_d;
  end
  wire old_use = is_shift2_r || ((aluop_r == ALUJMP_SHIFT) && (class_r == 4'd3));
  assign mismatch = old_use != use_r;
endmodule
