// z486.sv fetch_limit_rem: the CS-limit remainder's ">= 64" saturation.
// old: a 27-input OR over the 34-bit difference rem[32:6].
// new: the sign of a second chain, limit - 63 - EIP (rem >= 64 <=> it is >= 0).
// MUTANT=1 uses -64 (off by one; -62 would be benign: rem = 63 saturates to 63 either way) and must be refuted.
module fetch_limit_far #(parameter MUTANT = 0)
  (input G, input [19:0] limit, input [31:0] EIP, output mismatch);
  wire [33:0] lim = G ? {2'b0, limit, 12'hFFF} : {14'd0, limit};
  wire [33:0] rem = lim + 34'd1 - {2'b0, EIP};
  wire [33:0] far = lim - (MUTANT ? 34'd64 : 34'd63) - {2'b0, EIP};
  wire [5:0] old_r = rem[33] ? 6'd0 : (|rem[32:6]) ? 6'd63 : rem[5:0];
  wire [5:0] new_r = rem[33] ? 6'd0 : !far[33]     ? 6'd63 : rem[5:0];
  assign mismatch = old_r != new_r;
endmodule
