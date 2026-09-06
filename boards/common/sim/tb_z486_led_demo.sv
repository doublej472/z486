`timescale 1ns/1ps

module tb_z486_led_demo;

logic clk = 1'b0;
logic reset_n = 1'b0;
logic [7:0] led;
logic firmware_seen;
logic led_write_pulse;
logic [7:0] led_write_data;
logic triple_fault;
logic [15:0] dbg_cs;
logic [31:0] dbg_eip;
integer cycles;
integer writes;

`ifdef Z486_SIM_ENABLE_X87
localparam logic SIM_ENABLE_X87 = 1'b1;
`else
localparam logic SIM_ENABLE_X87 = 1'b0;
`endif

always #5 clk = ~clk;

z486_led_demo_soc #(
    .CLOCK_RATE_MHZ(7'd50),
    .FIRMWARE_HEX("boards/firmware/blink.hex"),
    .ENABLE_X87(SIM_ENABLE_X87)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .led(led),
    .firmware_seen(firmware_seen),
    .led_write_pulse(led_write_pulse),
    .led_write_data(led_write_data),
    .triple_fault(triple_fault),
    .dbg_cs(dbg_cs),
    .dbg_eip(dbg_eip)
);

always_ff @(posedge clk) begin
    if (!reset_n) begin
        cycles <= 0;
        writes <= 0;
    end else begin
        cycles <= cycles + 1;

        if (triple_fault)
            $fatal(1, "triple fault at %04x:%08x after %0d cycles",
                   dbg_cs, dbg_eip, cycles);

        if (led_write_pulse) begin
            case (writes)
                0: if (led_write_data !== 8'h55)
                       $fatal(1, "first LED write was %02x", led_write_data);
                1: if (led_write_data !== 8'haa)
                       $fatal(1, "second LED write was %02x", led_write_data);
                2: if (led_write_data !== 8'h55)
                       $fatal(1, "third LED write was %02x", led_write_data);
                default: ;
            endcase
            writes <= writes + 1;
            $display("LED write %0d: %02x at cycle %0d (%04x:%08x)",
                     writes + 1, led_write_data, cycles, dbg_cs, dbg_eip);
            if (writes == 2) begin
                $display("PASS: x86 firmware generated the LED pattern");
                $finish;
            end
        end

        if (cycles == 20_000_000)
            $fatal(1, "timeout: writes=%0d CS:EIP=%04x:%08x",
                   writes, dbg_cs, dbg_eip);
    end
end

initial begin
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset_n = 1'b1;
end

endmodule
