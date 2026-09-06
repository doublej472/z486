module kv260_top #(
    parameter LED_ACTIVE_LOW = 1'b1,
    parameter ENABLE_X87 = 1'b1
) (
    output logic [7:0] led
);

logic cpu_clk;
logic cpu_arst_n;
logic cpu_reset_n;
logic [7:0] logical_led;

system_wrapper platform (
    .cpu_clk(cpu_clk),
    .cpu_arst_n(cpu_arst_n)
);

reset_sync reset_release (
    .clk(cpu_clk),
    .arst_n(cpu_arst_n),
    .reset_n(cpu_reset_n)
);

z486_led_demo_soc #(
    .CLOCK_RATE_MHZ(7'd100),
    .ENABLE_X87(ENABLE_X87),
    .FIRMWARE_HEX("blink.hex")
) demo (
    .clk(cpu_clk),
    .reset_n(cpu_reset_n),
    .led(logical_led),
    .firmware_seen(),
    .led_write_pulse(),
    .led_write_data(),
    .triple_fault(),
    .dbg_cs(),
    .dbg_eip()
);

always_comb
    led = LED_ACTIVE_LOW ? ~logical_led : logical_led;

endmodule
