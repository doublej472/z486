`timescale 1ns/1ns

module tb_l1_cache;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;

    reg  [31:0] cpu_addr = 32'h0;
    reg  [31:0] cpu_din = 32'h0;
    wire [31:0] cpu_dout;
    reg   [3:0] cpu_be = 4'hF;
    reg         cpu_valid = 1'b0;
    reg         cpu_write = 1'b0;
    wire        cpu_ready;
    wire        cpu_wr_ready;
    reg         flush_req = 0;
    wire        flush_done;
    wire        cpu_resp_valid;
    wire        stores_drained;
    reg  [11:0] vipt_probe_offset = 12'd0;
    reg         vipt_probe_valid = 1'b0;
    wire        vipt_probe_ready;
    wire        vipt_probe_accepted;
    reg  [31:0] vipt_resolve_phys_addr = 32'd0;
    reg         vipt_resolve_valid = 1'b0;
    wire [31:0] vipt_resolve_data;
    wire        vipt_resolve_hit;

    wire [31:0] mem_addr;
    wire [31:0] mem_din;
    reg  [31:0] mem_dout = 32'h0;
    reg [127:0] mem_line_dout = 128'h0;
    wire  [3:0] mem_be;
    wire  [7:0] mem_burstcount;
    reg         mem_ready = 1'b0;
    wire        mem_valid;
    wire        mem_write;
    reg         mem_resp_valid = 1'b0;
    reg         mem_line_resp_valid = 1'b0;
    reg         mem_stall = 1'b0;
    reg         wide_mode = 1'b0;
    reg         wide_pending = 1'b0;
    reg  [31:0] wide_addr = 32'h0;
    integer     mem_request_count = 0;
    integer     narrow_response_count = 0;
    integer     line_response_count = 0;
    integer     mem_request_before;
    integer     narrow_response_before;
    integer     line_response_before;
    reg         check_uncached_order = 1'b0;
    reg         saw_uncached_write_104 = 1'b0;

    reg  [31:0] snoop_addr = 32'h0;
    reg         snoop_valid = 1'b0;

    l1_cache #(
        .SET_BITS(3)
    ) dut (
        .clk(clk),
        .reset(reset),

        .cpu_addr(cpu_addr),
        .cpu_preread_offset(cpu_addr[11:0]),
        .cpu_preread_priority(cpu_valid),
        .cpu_din(cpu_din),
        .cpu_dout(cpu_dout),
        .cpu_be(cpu_be),
        .cpu_valid(cpu_valid),
        .cpu_write(cpu_write),
        .cpu_uncacheable(cpu_addr[31:17] == 15'h5),
        .cpu_ready(cpu_ready),
        .cpu_wr_ready(cpu_wr_ready),
        .cpu_resp_valid(cpu_resp_valid),
        .stores_drained(stores_drained),
        .vipt_probe_offset(vipt_probe_offset),
        .vipt_probe_valid(vipt_probe_valid),
        .vipt_probe_ready(vipt_probe_ready),
        .vipt_probe_accepted(vipt_probe_accepted),
        .vipt_resolve_phys_addr(vipt_resolve_phys_addr),
        .vipt_resolve_valid(vipt_resolve_valid),
        .vipt_resolve_data(vipt_resolve_data),
        .vipt_resolve_hit(vipt_resolve_hit),

        .mem_addr(mem_addr),
        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_line_dout(mem_line_dout),
        .mem_be(mem_be),
        .mem_burstcount(mem_burstcount),
        .mem_busy(1'b0),
        .mem_valid(mem_valid),
        .mem_write(mem_write),
        .mem_ready(mem_ready),
        .mem_resp_valid(mem_resp_valid),
        .mem_line_resp_valid(mem_line_resp_valid),

        .snoop_addr(snoop_addr),
        .snoop_valid(snoop_valid),
        .store_patch_busy(1'b0),

        .flush_req(flush_req),
        .flush_busy(),
        .flush_done(flush_done),
        .cache_enable(1'b1)
    );

    reg [7:0] mem [0:4095];
    reg [31:0] rd_addr = 32'h0;
    reg [7:0] rd_left = 8'd0;

    task automatic mem_put32(input [31:0] addr, input [31:0] data);
    begin
        mem[addr + 0] = data[7:0];
        mem[addr + 1] = data[15:8];
        mem[addr + 2] = data[23:16];
        mem[addr + 3] = data[31:24];
    end
    endtask

    task automatic vipt_read(
        input [31:0] linear_addr,
        input [31:0] physical_addr,
        input        expected_hit,
        input [31:0] expected_data
    );
    begin
        do @(negedge clk); while (!vipt_probe_ready);
        vipt_probe_offset = linear_addr[11:0];
        vipt_probe_valid = 1'b1;
        @(negedge clk);
        vipt_probe_valid = 1'b0;
        vipt_resolve_phys_addr = physical_addr;
        vipt_resolve_valid = 1'b1;
        #1;
        if (vipt_resolve_hit !== expected_hit) begin
            $display("L1 VIPT HIT FAIL la=%08x pa=%08x got=%0b expected=%0b",
                     linear_addr, physical_addr, vipt_resolve_hit, expected_hit);
            $fatal(1);
        end
        if (expected_hit && vipt_resolve_data !== expected_data) begin
            $display("L1 VIPT DATA FAIL pa=%08x got=%08x expected=%08x",
                     physical_addr, vipt_resolve_data, expected_data);
            $fatal(1);
        end
        @(negedge clk);
        vipt_resolve_valid = 1'b0;
    end
    endtask

    function automatic [31:0] mem_get32(input [31:0] addr);
        if (addr[31:25] == 7'b0000001) begin
            case (addr[3:2])
                2'd0: mem_get32 = 32'h1357_9BDF;
                2'd1: mem_get32 = 32'h2468_ACE0;
                2'd2: mem_get32 = 32'h55AA_00FF;
                default: mem_get32 = 32'hAA55_FF00;
            endcase
        end else begin
            mem_get32 = {mem[addr[11:0] + 3], mem[addr[11:0] + 2],
                         mem[addr[11:0] + 1], mem[addr[11:0] + 0]};
        end
    endfunction

    always_ff @(posedge clk) begin
        mem_ready <= 1'b0;
        mem_resp_valid <= 1'b0;
        mem_line_resp_valid <= 1'b0;
        mem_dout <= 32'h0;

        if (wide_pending) begin
            mem_line_dout <= {mem_get32(wide_addr + 32'd12),
                              mem_get32(wide_addr + 32'd8),
                              mem_get32(wide_addr + 32'd4),
                              mem_get32(wide_addr)};
            mem_line_resp_valid <= 1'b1;
            wide_pending <= 1'b0;
            line_response_count <= line_response_count + 1;
        end

        if (rd_left != 8'd0) begin
            mem_resp_valid <= 1'b1;
            mem_dout <= mem_get32(rd_addr);
            rd_addr <= rd_addr + 32'd4;
            rd_left <= rd_left - 8'd1;
            narrow_response_count <= narrow_response_count + 1;
        end

        if (mem_valid && !mem_ready && rd_left == 8'd0 && !wide_pending &&
            !mem_stall) begin
            mem_ready <= 1'b1;
            mem_request_count <= mem_request_count + 1;
            if (mem_write) begin
                if (check_uncached_order && mem_addr == 32'h000A_0104)
                    saw_uncached_write_104 <= 1'b1;
                if (mem_be[0]) mem[mem_addr[11:0] + 0] <= mem_din[7:0];
                if (mem_be[1]) mem[mem_addr[11:0] + 1] <= mem_din[15:8];
                if (mem_be[2]) mem[mem_addr[11:0] + 2] <= mem_din[23:16];
                if (mem_be[3]) mem[mem_addr[11:0] + 3] <= mem_din[31:24];
            end else if (wide_mode && mem_burstcount == 8'd4) begin
                wide_addr <= mem_addr;
                wide_pending <= 1'b1;
            end else begin
                if (check_uncached_order && mem_addr == 32'h000A_0108 && !saw_uncached_write_104) begin
                    $display("L1 ORDER FAIL uncached read bypassed older posted write");
                    $fatal(1);
                end
                rd_addr <= mem_addr;
                rd_left <= mem_burstcount == 8'd0 ? 8'd1 : mem_burstcount;
            end
        end
    end

    task automatic cache_read(input [31:0] addr, input [3:0] be, input [31:0] expected);
    begin
        do @(negedge clk); while (!cpu_ready);
        cpu_addr = addr;
        cpu_be = be;
        cpu_din = 32'h0;
        cpu_write = 1'b0;
        cpu_valid = 1'b1;
        @(negedge clk);
        cpu_valid = 1'b0;
        if (!cpu_resp_valid)
            do @(negedge clk); while (!cpu_resp_valid);
        if (cpu_dout !== expected) begin
            $display("L1 READ FAIL addr=%08x got=%08x expected=%08x", addr, cpu_dout, expected);
            $fatal(1);
        end
    end
    endtask

    task automatic cache_write(input [31:0] addr, input [3:0] be, input [31:0] data);
    begin
        do @(negedge clk); while (!cpu_ready);
        cpu_addr = addr;
        cpu_be = be;
        cpu_din = data;
        cpu_write = 1'b1;
        cpu_valid = 1'b1;
        @(negedge clk);
        cpu_valid = 1'b0;
        cpu_write = 1'b0;
    end
    endtask

    task automatic demand_over_vipt(input [31:0] addr, input [31:0] expected);
    begin
        do @(negedge clk); while (!cpu_ready || !vipt_probe_ready);
        cpu_addr = addr;
        cpu_be = 4'hF;
        cpu_write = 1'b0;
        cpu_valid = 1'b1;
        vipt_probe_offset = addr[11:0];
        vipt_probe_valid = 1'b1;
        #1;
        if (vipt_probe_accepted) begin
            $display("L1 VIPT ARB FAIL: speculative probe beat demand");
            $fatal(1);
        end
        @(negedge clk);
        cpu_valid = 1'b0;
        vipt_probe_valid = 1'b0;
        if (!cpu_resp_valid)
            do @(negedge clk); while (!cpu_resp_valid);
        if (cpu_dout !== expected) begin
            $display("L1 VIPT ARB DATA FAIL got=%08x expected=%08x",
                     cpu_dout, expected);
            $fatal(1);
        end
        vipt_read(addr, addr, 1'b1, expected);
    end
    endtask

    // Two sets can occupy the same way RAM. Its single write port must not
    // lose a snoop clear when an unrelated fill completes on that edge.
    task automatic fill_snoop_collision(input bit wide, input bit cancel_fill);
    begin
        do @(negedge clk); while (!cpu_ready);
        reset = 1'b1;
        wide_mode = wide;
        repeat (5) @(negedge clk);
        reset = 1'b0;
        repeat (20) @(negedge clk);
        mem_put32(32'h40, 32'h1122_3344);
        mem_put32(32'h10, 32'h5566_7788);
        cache_read(32'h40, 4'hF, 32'h1122_3344);
        do @(negedge clk); while (!cpu_ready);
        mem_put32(32'h40, 32'hDEAD_BEEF);
        fork
            cache_read(32'h10, 4'hF, 32'h5566_7788);
            begin
                do @(negedge clk); while (!(dut.fill_count == 2'd2 &&
                    (wide ? dut.wide_fill_install : mem_resp_valid)));
                snoop_addr = 32'h40;
                snoop_valid = 1'b1;
                @(negedge clk);
                if (dut.fill_way != 0 || dut.fill_set != 1 ||
                    dut.snoop_set_r != 4 || !dut.snoop_valid_r)
                    $fatal(1, "D-cache fill/snoop collision was not exercised");
                // Keep the port busy with OTHER sets after this one-cycle
                // event: repeating 0x40 would hide a dropped first clear.
                snoop_addr = cancel_fill ? 32'h10 : 32'h80;
                if (cancel_fill) mem_put32(32'h10, 32'h8765_4321);
                repeat (3) @(negedge clk);
                snoop_valid = 1'b0;
            end
        join
        do @(negedge clk); while (!cpu_ready);
        mem_request_before = mem_request_count;
        cache_read(32'h10, 4'hF, cancel_fill ? 32'h8765_4321 : 32'h5566_7788);
        if (!cancel_fill && mem_request_count != mem_request_before)
            $fatal(1, "D-cache fill/snoop collision lost the unrelated fill");
        if (cancel_fill && mem_request_count == mem_request_before)
            $fatal(1, "D-cache deferred fill reinstated a later-snooped line");
        cache_read(32'h40, 4'hF, 32'hDEAD_BEEF);
        $display("D-cache different-set fill/snoop PASS wide=%0b cancel=%0b", wide, cancel_fill);
    end
    endtask

    initial begin
        fork
            begin
                repeat (5000) @(posedge clk);
                $display("L1 TIMEOUT state=%0d ready=%0b valid=%0b resp=%0b mem_valid=%0b mem_ready=%0b storeq_count=%0d",
                         dut.state, cpu_ready, cpu_valid, cpu_resp_valid,
                         mem_valid, mem_ready, dut.storeq_count);
                $fatal(1);
            end
        join_none

        for (integer i = 0; i < 4096; i = i + 1)
            mem[i] = 8'h00;

        mem_put32(32'h40, 32'h4433_2211);
        mem_put32(32'h44, 32'h8877_6655);
        mem_put32(32'h48, 32'hCCBB_AA99);
        mem_put32(32'h4C, 32'h00FF_EEDD);
        mem_put32(32'h80, 32'h0102_0304);

        repeat (5) @(posedge clk);
        reset <= 1'b0;
        repeat (20) @(posedge clk);

        cache_read(32'h40, 4'hF, 32'h4433_2211);       // miss + fill
        cache_read(32'h40, 4'hF, 32'h4433_2211);       // hit
        demand_over_vipt(32'h40, 32'h4433_2211);
        // The probe's tag read and snoop capture share this edge. Resolve in
        // the registered clearing cycle must miss just like a demand lookup.
        do @(negedge clk); while (!vipt_probe_ready);
        vipt_probe_offset = 12'h040;
        vipt_probe_valid = 1'b1;
        snoop_addr = 32'h40;
        snoop_valid = 1'b1;
        @(negedge clk);
        vipt_probe_valid = 1'b0;
        snoop_valid = 1'b0;
        vipt_resolve_phys_addr = 32'h40;
        vipt_resolve_valid = 1'b1;
        #1;
        if (vipt_resolve_hit)
            $fatal(1, "D-cache VIPT resolve hit in the registered snoop clear cycle");
        @(negedge clk);
        vipt_resolve_valid = 1'b0;
        cache_read(32'h40, 4'hF, 32'h4433_2211);
        vipt_read(32'h0000_0040, 32'h0000_0040, 1'b1, 32'h4433_2211);
        vipt_read(32'h0000_0040, 32'h0100_0040, 1'b0, 32'd0);
        // Complete physical tags distinguish lines separated by 32MB.
        cache_read(32'h0200_0040, 4'hF, 32'h1357_9BDF);
        cache_read(32'h40, 4'hF, 32'h4433_2211);
        mem_stall = 1'b1;
        cache_write(32'h40, 4'hC, 32'hAAAA_5555);      // write-hit patch
        vipt_read(32'h0000_0040, 32'h0000_0040, 1'b1, 32'hAAAA_2211);
        if (dut.storeq_count == 0) begin
            $display("L1 VIPT QUEUE TEST FAIL: posted store drained before probe");
            $fatal(1);
        end
        mem_stall = 1'b0;
        cache_read(32'h40, 4'hF, 32'hAAAA_2211);

        cache_write(32'h80, 4'hF, 32'hDEAD_BEEF);      // write miss, no allocate
        cache_read(32'h80, 4'hF, 32'hDEAD_BEEF);       // fill patched from store queue

        // Uncacheable reads must wait for every older posted store.  VGA uses
        // this ordering when it restores a software cursor before saving the
        // background at the cursor's next position.
        mem_stall = 1'b1;
        check_uncached_order = 1'b1;
        saw_uncached_write_104 = 1'b0;
        mem_put32(32'h108, 32'hA55A_C33C);
        fork
            begin
                cache_write(32'h000A_0100, 4'hF, 32'h1122_3344);
                cache_write(32'h000A_0104, 4'hF, 32'h5566_7788);
                // A different-address read still observes the preceding writes:
                // planar VGA read latches make ordering global to the aperture.
                cache_read(32'h000A_0108, 4'hF, 32'hA55A_C33C);
            end
            begin
                repeat (5) @(posedge clk);
                mem_stall = 1'b0;
            end
        join
        check_uncached_order = 1'b0;

        repeat (20) @(posedge clk);
        mem_put32(32'h40, 32'hCAFE_BABE);
        @(posedge clk);
        snoop_addr <= 32'h40;
        snoop_valid <= 1'b1;
        @(posedge clk);
        snoop_valid <= 1'b0;
        cache_read(32'h40, 4'hF, 32'hCAFE_BABE);       // snoop invalidated line

        // The KV260 DDR backend returns a complete 16-byte cache line in one
        // response. No four-DWORD response sequence is required at this port.
        mem_put32(32'h180, 32'h1800_0000);
        mem_put32(32'h184, 32'h1800_0001);
        mem_put32(32'h188, 32'h1800_0002);
        mem_put32(32'h18C, 32'h1800_0003);
        wide_mode = 1'b1;
        do @(negedge clk); while (!cpu_ready);
        mem_request_before = mem_request_count;
        narrow_response_before = narrow_response_count;
        line_response_before = line_response_count;
        cache_read(32'h188, 4'hF, 32'h1800_0002);
        if (line_response_count != line_response_before + 1 ||
            narrow_response_count != narrow_response_before) begin
            $display("L1 WIDE FILL response counts line=%0d narrow=%0d",
                     line_response_count, narrow_response_count);
            $fatal(1);
        end
        cache_read(32'h180, 4'hF, 32'h1800_0000);
        if (mem_request_count != mem_request_before + 1) begin
            $display("L1 WIDE FILL was not installed after one line response");
            $fatal(1);
        end

        fill_snoop_collision(1'b0, 1'b0);
        fill_snoop_collision(1'b1, 1'b0);
        fill_snoop_collision(1'b0, 1'b1);
        fill_snoop_collision(1'b1, 1'b1);

        // The flush arm must close the pipelined write opening immediately,
        // not only ready_r. The older accepted store still completes.
        do @(negedge clk); while (!cpu_wr_ready);
        cpu_addr = 32'h2C0;
        cpu_din = 32'hCAFE_BABE;
        cpu_write = 1;
        cpu_valid = 1;
        vipt_probe_offset = 12'h040; // shares set/word with the store preread
        vipt_probe_valid = 1;
        #1;
        if (!vipt_probe_accepted)
            $fatal(1, "flush/probe setup did not accept a shared preread");
        @(negedge clk);
        cpu_valid = 0;
        cpu_write = 0;
        vipt_probe_valid = 0;
        vipt_resolve_valid = 1;
        vipt_resolve_phys_addr = 32'h40;
        flush_req = 1;
        #1;
        if (cpu_wr_ready)
            $fatal(1, "pipelined store opening survived the flush arm");
        if (vipt_probe_ready || vipt_resolve_hit)
            $fatal(1, "VIPT lookup remained usable after the flush arm");
        @(negedge clk);
        flush_req = 0;
        vipt_resolve_valid = 0;
        do @(negedge clk); while (!flush_done);
        cache_read(32'h2C0, 4'hF, 32'hCAFE_BABE);

        $display("L1 PIPT cache unit test PASS");
        $finish;
    end
endmodule
