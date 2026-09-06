module de10nano_top #(
    parameter ENABLE_X87 = 1'b1,
    parameter integer CPU_MHZ = 50
) (
    input  logic       FPGA_CLK1_50,
    input  logic [1:0] KEY,
    output logic [7:0] LED
);

logic reset_n;
logic [7:0] logical_led;
logic cpu_clk;
logic pll_locked;

de10nano_pll #(
    .CPU_MHZ(CPU_MHZ)
) cpu_clock (
    .refclk(FPGA_CLK1_50),
    .reset(!KEY[0]),
    .cpu_clk(cpu_clk),
    .locked(pll_locked)
);

reset_sync reset_release (
    .clk(cpu_clk),
    .arst_n(KEY[0] && pll_locked),
    .reset_n(reset_n)
);

z486_led_demo_soc #(
    .CLOCK_RATE_MHZ(CPU_MHZ),
    .ENABLE_X87(ENABLE_X87),
    .FIRMWARE_HEX("blink.hex")
) demo (
    .clk(cpu_clk),
    .reset_n(reset_n),
    .led(logical_led),
    .firmware_seen(),
    .led_write_pulse(),
    .led_write_data(),
    .triple_fault(),
    .dbg_cs(),
    .dbg_eip()
);

always_comb
    LED = logical_led;

endmodule
