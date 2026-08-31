`timescale 1ns/1ns

module tb_memory_order;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset_n = 1'b0;

    reg         dcache_req_valid = 1'b0;
    reg  [31:0] dcache_req_phys_addr_raw = 32'h0;
    reg         dcache_req_write = 1'b0;
    reg   [3:0] dcache_req_be = 4'hF;
    reg  [31:0] dcache_req_wdata = 32'h0;
    reg         dcache_req_is_io = 1'b0;
    reg         dcache_req_is_vga_mem = 1'b0;
    wire        dcache_req_accepted;
    wire        dcache_req_complete;
    wire        dcache_read_complete;
    wire [31:0] dcache_rdata;

    wire [31:2] addr;
    wire  [3:0] be;
    wire  [7:0] burstcount;
    reg  [31:0] din = 32'h0;
    wire [31:0] dout;
    wire        valid;
    reg         ready = 1'b0;
    wire        write;
    wire        io;
    reg         resp_valid = 1'b0;
    wire        inta;

    memory #(
        .DCACHE_SET_BITS(3),
        .ICACHE_SET_BITS(3)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .a20_enable(1'b1),

        .dcache_req_valid(dcache_req_valid),
        .dcache_req_phys_addr_raw(dcache_req_phys_addr_raw),
        .dcache_req_preread_offset(12'h000),
        .dcache_req_preread_priority(1'b0),
        .dcache_req_write(dcache_req_write),
        .dcache_req_be(dcache_req_be),
        .dcache_req_wdata(dcache_req_wdata),
        .dcache_direct_wdata(dcache_req_wdata),
        .dcache_req_is_io(dcache_req_is_io),
        .dcache_req_is_inta(1'b0),
        .dcache_req_is_x87(1'b0),
        .dcache_req_is_vga_mem(dcache_req_is_vga_mem),
        .dcache_req_accepted(dcache_req_accepted),
        .dcache_req_complete(dcache_req_complete),
        .dcache_read_complete(dcache_read_complete),
        .dcache_rdata(dcache_rdata),

        .dcache_vipt_probe_valid(1'b0),
        .dcache_vipt_probe_offset(12'h000),
        .dcache_vipt_probe_ready(),
        .dcache_vipt_probe_accepted(),
        .dcache_vipt_resolve_valid(1'b0),
        .dcache_vipt_resolve_phys_addr_raw(32'h0),
        .dcache_vipt_resolve_hit(),
        .dcache_vipt_resolve_data(),

        .x87_req_selected(),
        .x87_req_accepted(1'b0),
        .x87_req_complete(1'b0),
        .x87_read_complete(1'b0),
        .x87_rdata(32'h0),

        .icache_req_valid(1'b0),
        .icache_req_phys_addr_raw(32'h0),
        .icache_req_accepted(),
        .icache_req_complete(),
        .icache_rdata(),

        .snoop_addr(32'h0),
        .snoop_valid(1'b0),

        .addr(addr),
        .be(be),
        .burstcount(burstcount),
        .din(din),
        .dout(dout),
        .valid(valid),
        .ready(ready),
        .write(write),
        .io(io),
        .resp_valid(resp_valid),
        .inta(inta)
    );

    initial begin
        fork
            begin
                repeat (500) @(posedge clk);
                $display("MEMORY ORDER TIMEOUT");
                $fatal(1);
            end
        join_none

        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (20) @(posedge clk);

        // Post a normal memory store while the external bus is stalled.
        // Present the following Sound Blaster-style port write as soon as the
        // CPU-side store is accepted, before it has reached external memory.
        @(negedge clk);
        dcache_req_phys_addr_raw = 32'h0000_1000;
        dcache_req_wdata = 32'hCAFE_BABE;
        dcache_req_write = 1'b1;
        dcache_req_is_io = 1'b0;
        dcache_req_valid = 1'b1;
        do @(negedge clk); while (!dcache_req_accepted);

        dcache_req_phys_addr_raw = 32'h0000_0220;
        dcache_req_wdata = 32'h0000_0014;
        dcache_req_write = 1'b1;
        dcache_req_is_io = 1'b1;

        do @(negedge clk); while (!valid);
        if (io || !write || addr !== 30'h0000_0400 ||
            dout !== 32'hCAFE_BABE) begin
            $display("MEMORY ORDER FAIL first external request: io=%0b write=%0b addr=%08x data=%08x",
                     io, write, {addr, 2'b00}, dout);
            $fatal(1);
        end

        // Accept the older store.  Only then may the port transaction appear.
        ready = 1'b1;
        @(negedge clk);
        ready = 1'b0;
        do @(negedge clk); while (!valid);
        if (!io || !write || addr !== 30'h0000_0088 ||
            dout !== 32'h0000_0014) begin
            $display("MEMORY ORDER FAIL second external request: io=%0b write=%0b addr=%08x data=%08x",
                     io, write, {addr, 2'b00}, dout);
            $fatal(1);
        end

        ready = 1'b1;
        @(negedge clk);
        dcache_req_valid = 1'b0;
        dcache_req_write = 1'b0;
        dcache_req_is_io = 1'b0;
        ready = 1'b0;

        // Reset the queue, then verify that a direct VGA-memory request can
        // win arbitration against an unrelated posted RAM-store drain.  VGA
        // transactions all use this direct path, so their mutual ordering is
        // still preserved.
        reset_n = 1'b0;
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (20) @(posedge clk);

        @(negedge clk);
        dcache_req_phys_addr_raw = 32'h0000_2000;
        dcache_req_wdata = 32'h1234_5678;
        dcache_req_write = 1'b1;
        dcache_req_is_io = 1'b0;
        dcache_req_is_vga_mem = 1'b0;
        dcache_req_valid = 1'b1;
        do @(negedge clk); while (!dcache_req_accepted);

        dcache_req_phys_addr_raw = 32'h000B_8000;
        dcache_req_write = 1'b0;
        dcache_req_is_vga_mem = 1'b1;

        do @(negedge clk); while (!valid);
        if (io || write || addr !== 30'h0002_E000) begin
            $display("MEMORY ORDER FAIL VGA bypass: io=%0b write=%0b addr=%08x",
                     io, write, {addr, 2'b00});
            $fatal(1);
        end

        $display("Memory device-ordering unit test PASS");
        $finish;
    end
endmodule
