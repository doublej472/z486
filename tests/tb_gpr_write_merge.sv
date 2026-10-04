`timescale 1ns/1ns
// Unit bench for gpr_write_merge.  The module is the single arbitration for the
// register producers that can be in flight at once, so these cases pin the
// rules the commit path and every forwarding view now share:
//   * the younger producer wins the byte lanes it owns,
//   * byte lanes it does not own keep the older producer's value,
//   * views differ only in visibility, never in order,
//   * an M3 ALU result is committed but never forwarded.
module tb_gpr_write_merge;
    import z486_pkg::*;

    // Must match the masks data_unit wires.  The recipe commits (bits 7:5) are
    // consolidated for the register-file write (pulse_value/pulse_wmask) but are
    // deliberately NOT forwarded, so no view mask sets them.
    localparam logic [7:0] VIS_EX  = 8'b0000_1010;   // mem, wb
    localparam logic [7:0] VIS_EA  = 8'b0001_1001;   // shift, wb, dly
    localparam logic [7:0] VIS_CAP = 8'b0001_1011;   // shift, mem, wb, dly

    logic [255:0] cur;
    logic         v_shift, v_mem, v_rom, v_wb, v_dly;
    logic [2:0]   dst_shift, dst_mem, dst_rom, dst_wb, dst_dly;
    logic [1:0]   size_shift, mode_mem, size_rom, size_wb, mode_dly;
    logic [31:0]  data_shift, data_mem, data_rom, data_wb, data_dly;
    logic         wb_is_alu;
    logic         v_stos, v_sigsrc, v_esp;
    logic [2:0]   dst_sigsrc;
    logic [1:0]   size_stos, size_sigsrc;
    logic [31:0]  data_stos, data_sigsrc, data_esp;
    logic [255:0] commit_value, commit_wmask, pulse_value, pulse_wmask;
    logic [255:0] ex_value, ea_value, cap_value;

    integer failures = 0;

    gpr_write_merge dut (
        .cur(cur),
        .v_shift(v_shift), .dst_shift(dst_shift), .size_shift(size_shift), .data_shift(data_shift),
        .v_mem(v_mem), .dst_mem(dst_mem), .mode_mem(mode_mem), .data_mem(data_mem),
        .v_rom(v_rom), .dst_rom(dst_rom), .size_rom(size_rom), .data_rom(data_rom),
        .v_wb(v_wb), .dst_wb(dst_wb), .size_wb(size_wb), .wb_is_alu(wb_is_alu), .data_wb(data_wb),
        .v_dly(v_dly), .dst_dly(dst_dly), .mode_dly(mode_dly), .data_dly(data_dly),
        .v_stos(v_stos), .size_stos(size_stos), .data_stos(data_stos),
        .v_sigsrc(v_sigsrc), .dst_sigsrc(dst_sigsrc), .size_sigsrc(size_sigsrc),
        .data_sigsrc(data_sigsrc),
        .v_esp(v_esp), .data_esp(data_esp),
        .vis_ex(VIS_EX), .vis_ea(VIS_EA), .vis_cap(VIS_CAP),
        .commit_value(commit_value), .commit_wmask(commit_wmask),
        .pulse_value(pulse_value), .pulse_wmask(pulse_wmask),
        .ex_value(ex_value), .ea_value(ea_value), .cap_value(cap_value)
    );

    function automatic [31:0] regval(input [255:0] v, input int r);
        regval = v[r*32 +: 32];
    endfunction

    task automatic check(input string name, input [31:0] got, input [31:0] want);
    begin
        if (got !== want) begin
            $display("GPR MERGE FAIL %s: got %08x want %08x", name, got, want);
            failures = failures + 1;
        end else begin
            $display("GPR MERGE PASS %s: %08x", name, got);
        end
    end
    endtask

    task automatic idle();
    begin
        v_shift = 1'b0; dst_shift = 3'd0; size_shift = 2'd2; data_shift = 32'd0;
        v_mem   = 1'b0; dst_mem   = 3'd0; mode_mem   = EA_FWD_D; data_mem = 32'd0;
        v_rom   = 1'b0; dst_rom   = 3'd0; size_rom   = 2'd2; data_rom = 32'd0;
        v_wb    = 1'b0; dst_wb    = 3'd0; size_wb    = 2'd2; wb_is_alu = 1'b0;
        data_wb = 32'd0;
        v_dly   = 1'b0; dst_dly   = 3'd0; mode_dly   = EA_FWD_D; data_dly = 32'd0;
        v_stos  = 1'b0; size_stos  = 2'd2; data_stos  = 32'd0;
        v_sigsrc= 1'b0; dst_sigsrc = 3'd0; size_sigsrc= 2'd2; data_sigsrc = 32'd0;
        v_esp   = 1'b0;                    data_esp   = 32'd0;
    end
    endtask

    initial begin
        idle();
        cur = 256'd0;

        // 1. Older dword token, younger dword write-back, same register.
        //    The younger producer must win the commit and every view.
        idle();
        cur = {224'd0, 32'h1111_1111};
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'hAAAA_AAAA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd2;     data_wb  = 32'hBBBB_BBBB;
        #1;
        check("1 ex view",     regval(ex_value, 0),     32'hBBBB_BBBB);
        check("1 commit",      regval(commit_value, 0), 32'hBBBB_BBBB);

        // 2. Older token owns byte 1 (AH), younger write-back owns byte 0 (AL).
        idle();
        cur = {224'd0, 32'h0000_1111};
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_BHI; data_mem = 32'h0000_00AA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd0;       data_wb  = 32'h0000_00BB;
        #1;
        check("2 disjoint lanes", regval(ex_value, 0), 32'h0000_AABB);

        // 2b. Byte producers address the register as dst[1:0] with dst[2]
        //     selecting AH/AL: an older byte to AH (dst=4) and a younger byte to
        //     AL (dst=0) must both land in the same register, disjointly.
        idle();
        cur = {224'd0, 32'h0000_0000};
        v_mem = 1'b1; dst_mem = 3'd4; mode_mem = EA_FWD_BHI; data_mem = 32'h0000_00AA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd0;       data_wb  = 32'h0000_00EF;
        #1;
        check("2b AH/AL encoding", regval(ex_value, 0), 32'h0000_AAEF);

        // 3. Older dword token, younger byte write-back: the byte wins, the
        //    token keeps the lanes the write-back does not own.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'hAAAA_AAAA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd0;     data_wb  = 32'h0000_00EF;
        #1;
        check("3 younger byte wins", regval(ex_value, 0), 32'hAAAA_AAEF);
        check("3 commit",            regval(commit_value, 0), 32'hAAAA_AAEF);

        // 4. Older byte token, younger dword write-back: the younger dword wins.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_BLO; data_mem = 32'h0000_00AA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd2;       data_wb  = 32'hBBBB_BBBB;
        #1;
        check("4 younger dword wins", regval(ex_value, 0), 32'hBBBB_BBBB);

        // 5. M3 ALU result: committed, never forwarded (it is derived from the
        //    views, so forwarding it would close a loop).  The result is
        //    right-aligned in its operand width, like every other producer.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'hAAAA_AAAA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd2; wb_is_alu = 1'b1;
        data_wb = 32'hCCCC_CCCC;
        #1;
        check("5 M3 not forwarded", regval(ex_value, 0),     32'hAAAA_AAAA);
        check("5 M3 committed",     regval(commit_value, 0), 32'hCCCC_CCCC);

        // 5b. M3 byte op into AH: the result is right-aligned, so it must be
        //     placed in byte 1 of the register, and still not forwarded.
        idle();
        cur = {224'd0, 32'h1234_1056};
        v_wb  = 1'b1; dst_wb  = 3'd4; size_wb  = 2'd0; wb_is_alu = 1'b1;
        data_wb = 32'h0000_0012;           // 0x10 + 2 in the operand width
        #1;
        check("5b M3 AH committed",  regval(commit_value, 0), 32'h1234_1256);
        check("5b M3 AH not forwarded", regval(ex_value, 0),  32'h1234_1056);

        // 6. Visibility: the EA view has no memory-token term (a D2 consumer of
        //    a still-pending load is interlocked), the capture view does.
        idle();
        cur = {224'd0, 32'h0000_2222};
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'h9999_9999;
        #1;
        check("6 ex sees token",       regval(ex_value, 0),  32'h9999_9999);
        check("6 ea hides token",      regval(ea_value, 0),  32'h0000_2222);
        check("6 capture sees token",  regval(cap_value, 0), 32'h9999_9999);

        // 7. Delay-slot bypass is youngest, and view-only.
        idle();
        cur = {224'd0, 32'h0000_0000};
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'h1111_1111;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd2;     data_wb  = 32'h2222_2222;
        v_dly = 1'b1; dst_dly = 3'd0; mode_dly = EA_FWD_W; data_dly = 32'h0000_3333;
        #1;
        check("7 ea: dly wins low word", regval(ea_value, 0),     32'h2222_3333);
        check("7 ea: wb wins upper",     regval(ea_value, 0) >> 16, 32'h2222);
        check("7 commit: no dly",        regval(commit_value, 0),  32'h2222_2222);

        // 8. The commit's byte mask is the union of the applied lanes, and the
        //    ROM slot sits between the memory token and the write-back.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_BHI; data_mem = 32'h0000_00AA;
        v_wb  = 1'b1; dst_wb  = 3'd0; size_wb  = 2'd0;       data_wb  = 32'h0000_00BB;
        v_rom = 1'b1; dst_rom = 3'd0; size_rom = 2'd1;       data_rom = 32'h0000_CCCC;
        #1;
        // The write-back is younger than the ROM slot, so its byte 0 wins over
        // the slot's word, and the union of the three lanes is the whole register.
        check("8 commit wmask", commit_wmask[31:0], 32'h0000_FFFF);
        check("8 wb byte wins over rom slot", regval(commit_value, 0), 32'h0000_CCBB);

        // 9. Different registers: producers must not cross lanes.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'h1111_1111;
        v_wb  = 1'b1; dst_wb  = 3'd2; size_wb  = 2'd2;     data_wb  = 32'h2222_2222;  // EDX
        #1;
        check("9 reg0 keeps token", regval(ex_value, 0), 32'h1111_1111);
        check("9 reg2 gets wb",     regval(ex_value, 2), 32'h2222_2222);
        check("9 reg1 untouched",   regval(ex_value, 1), 32'h0000_0000);

        // 10. A deferred-load token owns EAX while a SIGSRC recipe commit
        //     (MOVZX/MOVSX) writes EAX in the same cycle.  The commit path
        //     arbitrates them: the token is committed first and the younger
        //     recipe commit is applied on top.  The views deliberately do NOT
        //     forward the recipe commit (no younger consumer samples it in that
        //     cycle), so they show the token where mem is visible and cur where
        //     it is not.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'h0000_0044;
        v_sigsrc = 1'b1; dst_sigsrc = 3'd0; size_sigsrc = 2'd2; data_sigsrc = 32'h0000_0200;
        #1;
        check("10 pulse value",      regval(pulse_value, 0), 32'h0000_0200);
        check("10 pulse wmask",      pulse_wmask[31:0],      32'hFFFF_FFFF);
        check("10 token committed",  regval(commit_value, 0), 32'h0000_0044);
        check("10 ex hides commit",  regval(ex_value, 0),    32'h0000_0044);
        check("10 ea hides token",   regval(ea_value, 0),    32'h0000_0000);
        check("10 cap hides commit", regval(cap_value, 0),   32'h0000_0044);

        // 11. Lane granularity: a word SIGSRC writes only its two lanes.  The
        //     register file composes it over the committed token; the view shows
        //     the token unchanged.
        idle();
        cur = 256'd0;
        v_mem = 1'b1; dst_mem = 3'd0; mode_mem = EA_FWD_D; data_mem = 32'hAAAA_AAAA;
        v_sigsrc = 1'b1; dst_sigsrc = 3'd0; size_sigsrc = 2'd1; data_sigsrc = 32'hDDDD_CCCC;
        #1;
        check("11 pulse wmask word",    pulse_wmask[31:0],       32'h0000_FFFF);
        check("11 pulse word merge",    regval(pulse_value, 0),  32'h0000_CCCC);
        check("11 token committed",     regval(commit_value, 0), 32'hAAAA_AAAA);
        check("11 ex hides word commit",regval(ex_value, 0),     32'hAAAA_AAAA);

        // 12. The ESP recipe commit is the youngest producer of all, and the
        //     commit path applies it after the token, the write-back and the
        //     delay-slot bypass.  The views keep the base tier.
        idle();
        cur = 256'd0;
        v_mem  = 1'b1; dst_mem = 3'd4; mode_mem = EA_FWD_D; data_mem = 32'h1111_1111;
        v_wb   = 1'b1; dst_wb  = 3'd4; size_wb  = 2'd2;     data_wb  = 32'h2222_2222;
        v_dly  = 1'b1; dst_dly = 3'd4; mode_dly = EA_FWD_D; data_dly = 32'h3333_3333;
        v_esp  = 1'b1;                    data_esp = 32'h4444_4444;
        #1;
        check("12 esp commit value",  regval(pulse_value, 4), 32'h4444_4444);
        check("12 esp commit mask",   pulse_wmask[159:128],  32'hFFFF_FFFF);
        check("12 ex base wins wb",   regval(ex_value, 4),    32'h2222_2222);
        check("12 ea base wins dly",  regval(ea_value, 4),    32'h3333_3333);
        check("12 cap base wins dly", regval(cap_value, 4),   32'h3333_3333);

        // 13. Order among the recipe commits: SIGSRC (6) is younger than the REP
        //     STOS count (5), so it wins when both target ECX.
        idle();
        cur = 256'd0;
        v_stos = 1'b1; size_stos = 2'd2; data_stos = 32'h5555_5555;
        v_sigsrc = 1'b1; dst_sigsrc = 3'd1; size_sigsrc = 2'd2; data_sigsrc = 32'h6666_6666;
        #1;
        check("13 sigsrc younger than stos", regval(pulse_value, 1), 32'h6666_6666);

        // 14. A lone REP STOS count is a word write to ECX (reg 1): it merges
        //     into the current value and does not appear in the deferred commit.
        idle();
        cur = {192'd0, 32'h9999_9999, 32'h0000_0000};
        v_stos = 1'b1; size_stos = 2'd1; data_stos = 32'hEEEE_1234;
        #1;
        check("14 stos word merge",    regval(pulse_value, 1), 32'h9999_1234);
        check("14 stos wmask",         pulse_wmask[63:32],    32'h0000_FFFF);
        check("14 stos not in commit", commit_wmask[63:32],   32'h0000_0000);

        // 15. A recipe commit must not disturb other registers.
        idle();
        cur = 256'd0;
        v_sigsrc = 1'b1; dst_sigsrc = 3'd3; size_sigsrc = 2'd2; data_sigsrc = 32'h7777_7777;
        #1;
        check("15 target commit",    regval(pulse_value, 3), 32'h7777_7777);
        check("15 target mask only", pulse_wmask[127:96],    32'hFFFF_FFFF);
        check("15 others clean",     regval(pulse_value, 0), 32'h0000_0000);
        check("15 others clean",     regval(pulse_value, 7), 32'h0000_0000);

        $display("");
        if (failures == 0) begin
            $display("GPR WRITE MERGE TEST PASS");
        end else begin
            $display("GPR WRITE MERGE TEST FAIL: %0d case(s)", failures);
        end
        $finish;
    end

    initial begin
        repeat (1000) #1;
        $display("GPR WRITE MERGE TEST FAIL timeout");
        $finish;
    end
endmodule
