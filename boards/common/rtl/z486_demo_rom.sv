`include "z486_platform.svh"

module z486_demo_rom #(
    parameter INIT_HEX = "boards/firmware/blink.hex"
) (
    input  logic        clk,
    input  logic [13:0] address,
    output logic [31:0] q
);

`Z486_BLOCK_RAM logic [31:0] words [0:16383];

initial
    $readmemh(INIT_HEX, words);

always_ff @(posedge clk)
    q <= words[address];

endmodule
