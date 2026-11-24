`timescale 1ns/1ns
// SPDX-License-Identifier: GPL-3.0-or-later
// z486 lockstep harness top (test-only, never synthesized; see ../README.md).
// Memory, I/O and the comparison against the 86Box reference live in C++
// (lock.cpp) behind DPI calls; this module owns the clock, the reset-time
// register forcing (as tests/tb_z486.sv does it) and a latency-randomised
// ready/valid bus model.
module tb_lock;
    import "DPI-C" function int  ls_init(input int idx);
    import "DPI-C" function int  ls_rd32(input int a);
    import "DPI-C" function void ls_wr(input int a, input int be, input int d);
    import "DPI-C" function int  ls_io_rd(input int a, input int be);
    import "DPI-C" function void ls_io_wr(input int a, input int be, input int d);
    import "DPI-C" function int  ls_lat(input int w);
    import "DPI-C" function int  ls_a20();
    import "DPI-C" function int  ls_intr();
    import "DPI-C" function int  ls_inta(input int second);
    import "DPI-C" function int  ls_tick(input int issue, input int ieip, input int hstable,
                                         input int tfr, input int done, input int ssv, input int v[64]);

    localparam SEG_ES = 0, SEG_CS = 1, SEG_SS = 2, SEG_DS = 3, SEG_FS = 4, SEG_GS = 5;

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;

    wire [31:2] addr;
    wire [3:0]  be;
    wire [7:0]  burstcount;
    wire        line_read;
    wire [31:0] dout;
    wire        valid, write, io;
    reg  [31:0] din = 0;
    reg [127:0] line_din = 0;
    reg         ready = 0, resp_valid = 0, line_resp_valid = 0;
    reg         single_step = 0;
    reg         a20 = 1;
    reg         intr_r = 0;
    reg         inta_second = 0;
    wire        inta;
    wire        tfr;
    wire        issue, halted_w;
    wire [31:0] issue_eip;
    wire gate_rd;
    wire [31:0] gate_addr;
    bit trg = 0;
    initial trg = $test$plusargs("trace_gate");
    always @(posedge clk) if (trg && gate_rd) $display("GATE read %08x (vector %0d if IDT base 8C000)", gate_addr, (gate_addr - 32'h8C000) / 8);

    z486 dut (
        .clk(clk), .reset_n(reset_n),
        .device_mmio_enable(1'b0), .device_mmio_base(32'h0),
        .win0_unmapped(1'b0), .ram_cache_top(32'hffff_ffff),
        .addr(addr), .be(be), .burstcount(burstcount), .line_read(line_read),
        .din(din), .line_din(line_din), .dout(dout), .valid(valid), .ready(ready),
        .write(write), .io(io), .resp_valid(resp_valid), .line_resp_valid(line_resp_valid),
        .intr(intr_r), .nmi(1'b0), .inta(inta),
        .snoop_addr(32'h0), .snoop_valid(1'b0),
        .cache_flush(1'b0), .cache_flush_busy(), .cache_flush_done(),
        .a20_enable(a20),
        .fast_off_req(1'b0), .cache_off_req(1'b0), .x87_off_req(1'b0),
        .single_step(single_step),
        .dbg_CS(), .dbg_EIP(), .dbg_CS_base(), .dbg_pe(), .dbg_vm(), .dbg_x87_state(),
        .dbg_gate_read(gate_rd), .dbg_gate_addr(gate_addr), .dbg_pf_code(), .dbg_pf_addr(), .dbg_eflags(),
        .dbg_page_fault(), .dbg_walk_pde(), .dbg_walk_pte(), .dbg_cr3(), .dbg_SP(),
        .dbg_issue(issue), .dbg_issue_eip(issue_eip), .dbg(),
        .triple_fault_reset(tfr), .lock()
    );
    assign halted_w = dut.halted;

    // ------------------------------------------------------------ bus model
    reg        busy = 0;
    int        wait_n = 0;
    reg [31:0] rbase;
    reg [7:0]  rrem, ridx;
    reg        rio, rline;
    reg [3:0]  rbe;
    reg        inta_cyc = 0;
    reg [31:0] inta_resp = 0;
    always @(posedge clk) begin
        resp_valid <= 1'b0;
        line_resp_valid <= 1'b0;
        if (!reset_n) begin
            ready <= 1'b0;
            busy <= 1'b0;
        end else if (busy) begin
            if (wait_n > 0)
                wait_n <= wait_n - 1;
            else if (rrem != 0) begin
                if (rline) begin
                    line_din <= {ls_rd32(rbase + 12), ls_rd32(rbase + 8), ls_rd32(rbase + 4), ls_rd32(rbase)};
                    line_resp_valid <= 1'b1;
                    rrem <= 0;
                end else begin
                    din <= inta_cyc ? inta_resp : rio ? ls_io_rd(rbase, {28'h0, rbe}) : ls_rd32(rbase + {22'h0, ridx, 2'b00});
                    resp_valid <= 1'b1;
                    ridx <= ridx + 1;
                    rrem <= rrem - 1;
                end
            end else begin
                busy <= 1'b0;
                ready <= 1'b1;
            end
        end else begin
            ready <= 1'b1;
            if (valid && ready) begin
                int l;
                if (write) begin
                    if (io) ls_io_wr({addr, 2'b00}, {28'h0, be}, dout);
                    else    ls_wr({addr, 2'b00}, {28'h0, be}, dout);
                    l = ls_lat(1);
                    if (l > 0) begin
                        busy <= 1'b1; ready <= 1'b0; wait_n <= l - 1; rrem <= 0;
                    end
                end else if (inta) begin
                    busy <= 1'b1; ready <= 1'b0; wait_n <= 1;
                    rbase <= 0; rio <= 1'b1; rbe <= be; rline <= 1'b0; rrem <= 8'd1; ridx <= 0;
                    inta_resp <= ls_inta({31'h0, inta_second});
                    inta_second <= !inta_second;
                    inta_cyc <= 1'b1;
                end else begin
                    l = ls_lat(0);
                    inta_cyc <= 1'b0;
                    busy <= 1'b1;
                    ready <= 1'b0;
                    wait_n <= l & 255;
                    rbase <= {addr, 2'b00};
                    rio <= io;
                    rbe <= be;
                    rline <= !io && line_read && (burstcount == 8'd4) && ((l & 256) != 0);
                    rrem <= io ? 8'd1 : (burstcount == 8'd0 ? 8'd1 : burstcount);
                    ridx <= 0;
                end
            end
        end
    end

    // ------------------------------------------------------------ drain / state
    wire drained = !(dut.memory_inst.cache_unit_inst.dcache_inst.storeq_count != 0 ||
                     dut.memory_inst.cache_unit_inst.dcache_inst.storeq_draining ||
                     dut.memory_inst.cache_unit_inst.dcache_inst.mem_valid_r ||
                     dut.memory_inst.bus_unit_inst.dcache_direct_req ||
                     (dut.memory_inst.ext_valid_r && dut.memory_inst.bus_unit_inst.ext_write_r)) &&
                   !busy && !valid;
    int hcnt = 0, hcnt2 = 0;
    int v [64];
    always_comb begin
        for (int k = 0; k < 64; k++) v[k] = 0;
        v[0] = dut.EAX; v[1] = dut.ECX; v[2] = dut.EDX; v[3] = dut.EBX;
        v[4] = dut.ESP; v[5] = dut.EBP; v[6] = dut.ESI; v[7] = dut.EDI;
        v[8] = dut.EIP; v[9] = dut.EFLAGS; v[10] = dut.debug_ip;
        v[11] = {16'h0, dut.ES}; v[12] = {16'h0, dut.CS}; v[13] = {16'h0, dut.SS};
        v[14] = {16'h0, dut.DS}; v[15] = {16'h0, dut.FS}; v[16] = {16'h0, dut.GS};
        for (int k = 0; k < 6; k++) begin
            v[17 + 3*k] = dut.seg_unit.desc_cache[k].base;
            v[18 + 3*k] = {12'h0, dut.seg_unit.desc_cache[k].limit};
            v[19 + 3*k] = {16'h0, dut.seg_unit.desc_cache[k].seg_type, dut.seg_unit.desc_cache[k].S,
                           dut.seg_unit.desc_cache[k].DPL, dut.seg_unit.desc_cache[k].P,
                           dut.seg_unit.desc_cache[k].D_B, dut.seg_unit.desc_cache[k].G,
                           dut.seg_unit.desc_cache[k].A, 5'h0};
        end
        v[35] = dut.CR0; v[36] = dut.CR2; v[37] = dut.CR3;
        v[38] = {30'h0, dut.cpl};
        v[39] = {16'h0, dut.LDTR}; v[40] = {16'h0, dut.TR};
        v[41] = dut.DR6; v[42] = dut.DR7;
    end

    int ctl;
    bit trc = 0;
    // experiment (+fixcpl): drop a pending CPL transition when a fault is taken
    bit fixcpl = 0;
    initial fixcpl = $test$plusargs("fixcpl");
    always @(posedge clk)
        if (fixcpl && dut.any_fault && dut.protection_unit_inst.cpl_transition_r) begin
            $display("FIXCPL: clearing a pending CPL transition at a fault (pending %0d)", dut.protection_unit_inst.pending_cpl_r);
            dut.protection_unit_inst.cpl_transition_r <= 1'b0;
        end
    initial trc = $test$plusargs("trace");
    // Serialised issue through the core's own instruction-breakpoint hold
    // (z486.sv ibp_ok_r: issue only from a settled idle): ctl bit0 = serialise,
    // bit1 = go (let the next instruction issue), bit2 = finish.
    reg nat_r = 1, set_r = 0, ser = 0, go = 1, dbm_r = 0, ser_r = 0;
    always @(posedge clk) begin
        nat_r <= !(|dut.dr_exec_en) || (dut.ibp_settled && !dut.ibp_due);
        set_r <= dut.ibp_settled;
        dbm_r <= reset_n && dut.db_mode_next;
        ser_r <= ser;
    end
    // (db_mode_r: the core's DR7-enabled mode, which also turns off the port-B
    //  dead-slot overlap and the direct store path, as an armed breakpoint does)
    initial force dut.ibp_ok_r = nat_r && (!ser || (set_r && go));
    bit dbm_force = 0;
    initial dbm_force = $test$plusargs("dbmode");
    initial force dut.db_mode_r = dbm_r || ser_r || dbm_force;
    wire settled = !dut.uc_active && !issue && drained && !dut.stall;
    always @(posedge clk) begin
        if (reset_n && trc)
            $display("T %0t ua=%03x ep=%03x op=%02x iss=%b ieip=%08x uca=%b rni_d=%b stall=%b ser=%b go=%b eip=%08x ebx=%08x eax=%08x dr=%b hc=%0d",
                     $time, dut.uc_addr, dut.i.entry_point, dut.i.opcode, issue, issue_eip, dut.uc_active, dut.i_rni_delay, dut.stall, ser, go, dut.EIP, dut.EBX, dut.EAX, drained, hcnt);
        if (reset_n) begin
            hcnt <= settled ? hcnt + 1 : 0;
            hcnt2 <= (halted_w && drained) ? hcnt2 + 1 : 0;
            ctl = ls_tick({31'h0, issue}, issue_eip,
                          {30'h0, (hcnt2 >= 4), (hcnt >= 3) && settled}, {31'h0, tfr},
                          {31'h0, dut.i_rni_delay && !dut.stall && !dut.frontend_fault}, {31'h0, single_step}, v);
            ser <= ctl[0];
            single_step <= ctl[3];
            a20 <= ls_a20() != 0;
            intr_r <= ls_intr() != 0;
            go <= ctl[1];
            if (ctl[2]) $finish;
        end
    end

    // ------------------------------------------------------------ reset-time state
    int cr0_a, cr3_a, eflags_a, eip_a, cs_a, ds_a, es_a, ss_a, fs_a, gs_a;
    int g [8];
    int ss0;
    initial begin
        cr0_a = ls_init(0); cr3_a = ls_init(1);
        for (int k = 0; k < 8; k++) g[k] = ls_init(2 + k);
        eflags_a = ls_init(10);
        es_a = ls_init(11); cs_a = ls_init(12); ss_a = ls_init(13);
        ds_a = ls_init(14); fs_a = ls_init(15); gs_a = ls_init(16);
        eip_a = ls_init(17);
        ss0 = ls_init(18); ser = ss0[0]; go = 1;
        #20;
        reset_n = 0;
        #10;
        force dut.CR0 = cr0_a;
        force dut.CR3 = cr3_a;
        force dut.data_unit_inst.eax = g[0];
        force dut.data_unit_inst.ecx = g[1];
        force dut.data_unit_inst.edx = g[2];
        force dut.data_unit_inst.ebx = g[3];
        force dut.data_unit_inst.esp = g[4];
        force dut.data_unit_inst.ebp = g[5];
        force dut.data_unit_inst.esi = g[6];
        force dut.data_unit_inst.edi = g[7];
        force dut.data_unit_inst.eflags = eflags_a;
        force dut.CS = cs_a[15:0];
        force dut.DS = ds_a[15:0];
        force dut.ES = es_a[15:0];
        force dut.SS = ss_a[15:0];
        force dut.FS = fs_a[15:0];
        force dut.GS = gs_a[15:0];
        force dut.EIP = eip_a;
        force dut.seg_unit.seg_init_cs = z486_pkg::seg_desc_real_mode_code(cs_a[15:0]);
        force dut.seg_unit.seg_init_ds = z486_pkg::seg_desc_real_mode(ds_a[15:0]);
        force dut.seg_unit.seg_init_es = z486_pkg::seg_desc_real_mode(es_a[15:0]);
        force dut.seg_unit.seg_init_ss = z486_pkg::seg_desc_real_mode(ss_a[15:0]);
        force dut.seg_unit.seg_init_fs = z486_pkg::seg_desc_real_mode(fs_a[15:0]);
        force dut.seg_unit.seg_init_gs = z486_pkg::seg_desc_real_mode(gs_a[15:0]);
        force dut.prefetch_inst.pf_fetch_addr = {12'h0, cs_a[15:0], 4'h0} + eip_a;
        #50;
        reset_n = 1;
        release dut.CR0;
        release dut.CR3;
        release dut.data_unit_inst.eax;
        release dut.data_unit_inst.ecx;
        release dut.data_unit_inst.edx;
        release dut.data_unit_inst.ebx;
        release dut.data_unit_inst.esp;
        release dut.data_unit_inst.ebp;
        release dut.data_unit_inst.esi;
        release dut.data_unit_inst.edi;
        release dut.data_unit_inst.eflags;
        release dut.CS;
        release dut.DS;
        release dut.ES;
        release dut.SS;
        release dut.FS;
        release dut.GS;
        release dut.EIP;
        release dut.prefetch_inst.pf_fetch_addr;
        release dut.seg_unit.seg_init_cs;
        release dut.seg_unit.seg_init_ds;
        release dut.seg_unit.seg_init_es;
        release dut.seg_unit.seg_init_ss;
        release dut.seg_unit.seg_init_fs;
        release dut.seg_unit.seg_init_gs;
    end
endmodule
