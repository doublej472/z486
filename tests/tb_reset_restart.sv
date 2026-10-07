// One-cycle reset on a live instruction boundary must beat restart captures.
`timescale 1ns/1ns
module tb_reset_restart;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    wire [31:2] addr;
    wire valid, write, line_read;
    reg resp_valid = 0;
    reg line_resp_valid = 0;
    reg [127:0] line_din = 0;
    z486 dut (
        .clk(clk), .reset_n(reset_n),
        .device_mmio_enable(1'b0), .device_mmio_base(32'd0),
        .win0_unmapped(1'b0), .ram_cache_top(32'hffff_ffff),
        .addr(addr), .be(), .burstcount(), .dout(), .valid(valid),
        .write(write), .io(), .line_read(line_read),
        .ready(1'b1), .din(32'h9090_9090), .line_din(line_din),
        .resp_valid(resp_valid), .line_resp_valid(line_resp_valid),
        .intr(1'b0), .nmi(1'b0), .inta(),
        .snoop_valid(1'b0), .snoop_addr(32'd0),
        .cache_flush(1'b0), .cache_flush_busy(), .cache_flush_done(),
        .a20_enable(1'b1), .cpu_speed_sel(2'd0),
        .fast_off_req(1'b0), .cache_off_req(1'b0), .x87_off_req(1'b0),
        .single_step(1'b0),
        .triple_fault_reset()
    );
    // The reset vector executes MOV SP,1234h and then NOPs. Respond once per
    // accepted bus read; fills use the real whole-line response interface.
    always @(posedge clk) begin
        resp_valid <= valid && !write && !line_read;
        line_resp_valid <= valid && !write && line_read;
        line_din <= (addr[15:2] == 14'h3ffc)
                    ? 128'h90909090_90909090_90909090_901234bc
                    : {16{8'h90}};
    end
    initial begin
        fork begin repeat (2000) @(posedge clk); $fatal(1, "reset bench timeout"); end join_none
        repeat (5) @(negedge clk);
        reset_n = 1;
        do @(negedge clk); while (!(dut.ESP == 32'h1234 && dut.i_first));
        // i_first is still high from an actual issued instruction; resetting
        // it on this edge must not capture the OLD nonzero ESP over TMPeSP=0.
        reset_n = 0;
        @(negedge clk);
        if (dut.TMPeSP != 0 || dut.TMPeIP != 32'hfff0 ||
            dut.wr_restart_esp != 0 || dut.wr_restart_eip != 32'hfff0)
            $fatal(1, "live restart capture overwrote reset state: IP=%08x SP=%08x",
                   dut.TMPeIP, dut.TMPeSP);
        $display("RESET RESTART TEST PASS");
        $finish;
    end
endmodule
