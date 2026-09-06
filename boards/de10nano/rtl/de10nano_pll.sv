module de10nano_pll #(
    parameter integer CPU_MHZ = 50
) (
    input  wire refclk,
    input  wire reset,
    output wire cpu_clk,
    output wire locked
);

wire [0:0] outclk;

generate
    if (CPU_MHZ == 85) begin : gen_pll_85
        altera_pll #(
            .fractional_vco_multiplier("false"),
            .reference_clock_frequency("50.0 MHz"),
            .operation_mode("direct"),
            .number_of_clocks(1),
            .output_clock_frequency0("85.000000 MHz"),
            .phase_shift0("0 ps"),
            .duty_cycle0(50),
            .pll_type("General"),
            .pll_subtype("General")
        ) pll (
            .rst(reset),
            .outclk(outclk),
            .locked(locked),
            .fboutclk(),
            .fbclk(1'b0),
            .refclk(refclk)
        );
    end else begin : gen_pll_50
        altera_pll #(
            .fractional_vco_multiplier("false"),
            .reference_clock_frequency("50.0 MHz"),
            .operation_mode("direct"),
            .number_of_clocks(1),
            .output_clock_frequency0("50.000000 MHz"),
            .phase_shift0("0 ps"),
            .duty_cycle0(50),
            .pll_type("General"),
            .pll_subtype("General")
        ) pll (
            .rst(reset),
            .outclk(outclk),
            .locked(locked),
            .fboutclk(),
            .fbclk(1'b0),
            .refclk(refclk)
        );
    end
endgenerate

assign cpu_clk = outclk[0];

endmodule
