`timescale 1ns/1ns

// Unit test for interrupt_controller: an NMI edge latched in the
// accept-to-SETNMI window, or inside the handler, must not re-dispatch
// nested, and must be delivered only after CLRNMI (post-IRET).
module tb_interrupt_nmi;
    import z486_pkg::*;

    reg clk = 0;
    always #5 clk = ~clk;

    reg        reset_n = 0;
    reg        intr = 0;
    reg        nmi = 0;
    reg        iflag = 0;
    reg        i_rni = 0;
    reg        shadow_start = 0;
    reg        uc_exec = 0;
    reg  [6:0] uc_aluop = 0;
    reg        nmi_accept_boundary = 0;

    wire intr_pending;
    wire nmi_request_active;
    wire interrupt_pending;
    wire inhibit_interrupts;

    interrupt_controller dut (
        .clk(clk),
        .reset_n(reset_n),
        .intr(intr),
        .nmi(nmi),
        .iflag(iflag),
        .i_rni(i_rni),
        .shadow_start(shadow_start),
        .shadow_ss(1'b0),
        .uc_exec(uc_exec),
        .uc_aluop(uc_aluop),
        .nmi_accept_boundary(nmi_accept_boundary),
        .intr_pending(intr_pending),
        .nmi_request_active(nmi_request_active),
        .interrupt_pending(interrupt_pending),
        .inhibit_interrupts(inhibit_interrupts)
    );

    integer errors = 0;
    integer window_cycles = 0;

    // Advance one clock and let all edge-triggered activity settle before the
    // stimulus blocks read the outputs.
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic check(input logic cond, input string what);
        if (!cond) begin
            errors = errors + 1;
            $display("  CHECK FAIL: %s", what);
        end else begin
            $display("  check ok:   %s", what);
        end
    endtask

    task automatic apply_reset();
        reset_n = 1'b0;
        nmi = 1'b0;
        intr = 1'b0;
        uc_exec = 1'b0;
        uc_aluop = 7'd0;
        nmi_accept_boundary = 1'b0;
        i_rni = 1'b0;
        shadow_start = 1'b0;
        iflag = 1'b0;
        repeat (4) tick();
        reset_n = 1'b1;
        tick();
    endtask

    // Run the window scenario. When `extra_edge` is set a second NMI edge is
    // placed after the accept and before SETNMI; otherwise the window is clean.
    // `nested_after_setnmi` is nmi_request_active the cycle after SETNMI (must
    // be 0: no nested redispatch); `post_iret_request` is nmi_request_active
    // after CLRNMI releases the deferred edge.
    task automatic run_window(input logic extra_edge,
                              output logic nested_after_setnmi,
                              output logic post_iret_request);
        apply_reset();
        window_cycles = 0;

        // (1) NMI edge arrives and is latched while no boundary is present.
        nmi = 1'b1;
        tick();
        check(nmi_request_active === 1'b1, "NMI edge latched (request active, no boundary)");
        check(dut.nmi_pending === 1'b1, "nmi_pending latch set for the edge");

        // (2) A boundary accepts the NMI exactly once; the accept consumes the
        //     pending latch (nmi_pending & nmi_edge == 0 here, same-cycle edge
        //     is not present because nmi was already high).
        nmi_accept_boundary = 1'b1;
        check(nmi_request_active === 1'b1, "request active in the accept cycle");
        tick();
        nmi_accept_boundary = 1'b0;
        check(dut.nmi_pending === 1'b0, "accept consumed the pending latch");
        check(nmi_request_active === 1'b0, "no request remains after the accept");

        // (3) The NMI handler entry micro-op (SETNMI) has NOT executed yet:
        //     nmi_blocked is still low. This is the 486-forbidden window.
        check(dut.nmi_blocked === 1'b0, "nmi_blocked still low before SETNMI");

        if (extra_edge) begin
            // Controlled second edge inside the window: drop high, then raise.
            nmi = 1'b0;
            tick();
            window_cycles = window_cycles + 1;
            nmi = 1'b1;
            tick();
            window_cycles = window_cycles + 1;
            check(dut.nmi_pending === 1'b1, "second edge latched while nmi_blocked is low");
            check(nmi_request_active === 1'b1, "second request is live before SETNMI");
        end

        // (4) Handler entry: ALUJMP_SETNMI raises nmi_blocked.
        uc_exec = 1'b1;
        uc_aluop = ALUJMP_SETNMI;
        tick();
        uc_exec = 1'b0;
        uc_aluop = 7'd0;
        check(dut.nmi_blocked === 1'b1, "SETNMI raised nmi_blocked");

        // FIXED behavior: the window edge is deferred, not re-dispatched nested.
        nested_after_setnmi = nmi_request_active;
        check(nested_after_setnmi === 1'b0,
              "no request re-dispatched after SETNMI (nmi_blocked gates nmi_pending)");

        // The IRET unmask (CLRNMI) releases the deferred edge: a true
        // post-IRET delivery when the window held an edge, nothing otherwise.
        uc_exec = 1'b1;
        uc_aluop = ALUJMP_CLRNMI;
        tick();
        uc_exec = 1'b0;
        uc_aluop = 7'd0;
        check(dut.nmi_blocked === 1'b0, "CLRNMI cleared nmi_blocked");
        post_iret_request = nmi_request_active;
    endtask

    logic nested_window;
    logic post_iret_window;
    logic nested_control;
    logic post_iret_control;
    logic blocked_edge_latched;

    initial begin
        $display("");
        $display("========================================");
        $display("  NMI deferred-delivery cross-check");
        $display("========================================");

        // ---- Scenario A: edge in the accept-to-SETNMI window ----------------
        $display("");
        $display("[A] NMI edge inside the accept-to-SETNMI window:");
        run_window(1'b1, nested_window, post_iret_window);
        $display("    window length: %0d cycles after accept", window_cycles);
        $display("    nmi_request_active after SETNMI = %b", nested_window);
        check(nested_window === 1'b0, "no nested redispatch after SETNMI");
        check(post_iret_window === 1'b1,
              "window edge delivered after CLRNMI (post-IRET)");

        // ---------------------------------------------------------------------
        // Scenario B: control - no edge in the window.
        // ---------------------------------------------------------------------
        $display("");
        $display("[B] Control: single NMI, no edge in the window:");
        run_window(1'b0, nested_control, post_iret_control);
        $display("    nmi_request_active after SETNMI = %b", nested_control);
        check(nested_control === 1'b0, "clean window leaves no request pending");
        check(post_iret_control === 1'b0,
              "clean window delivers nothing after CLRNMI");

        // ---------------------------------------------------------------------
        // Scenario C: an edge AFTER SETNMI (inside the handler) is held, not
        // delivered, and is delivered after CLRNMI. Intel486 DX data sheet
        // (Oct 1992) 2.7.4: "If NMI occurs while currently servicing an NMI,
        // its presence will be saved for servicing after executing the first
        // IRET instruction."
        // ---------------------------------------------------------------------
        $display("");
        $display("[C] NMI edge after SETNMI is held until CLRNMI:");
        apply_reset();
        nmi = 1'b1;
        tick();
        nmi_accept_boundary = 1'b1;
        tick();
        nmi_accept_boundary = 1'b0;
        uc_exec = 1'b1;
        uc_aluop = ALUJMP_SETNMI;
        tick();
        uc_exec = 1'b0;
        uc_aluop = 7'd0;
        check(dut.nmi_blocked === 1'b1, "nmi_blocked set");
        // New edge: low then high.
        nmi = 1'b0;
        tick();
        nmi = 1'b1;
        tick();
        blocked_edge_latched = dut.nmi_pending;
        check(nmi_request_active === 1'b0,
              "edge after SETNMI is not delivered while nmi_blocked");
        check(blocked_edge_latched === 1'b1,
              "edge after SETNMI is held in nmi_pending");
        nmi = 1'b0;
        repeat (3) tick();
        check(nmi_request_active === 1'b0, "still held while the handler runs");
        uc_exec = 1'b1;
        uc_aluop = ALUJMP_CLRNMI;
        tick();
        uc_exec = 1'b0;
        uc_aluop = 7'd0;
        check(nmi_request_active === 1'b1, "held edge delivered after CLRNMI");

        // ---------------------------------------------------------------------
        // Scenario D: INTR is a level. A request withdrawn before the boundary
        // is gone (Intel486 DX data sheet, Oct 1992, 6.4.1: "The interrupt
        // will not be serviced ... if the INTR signal does not remain
        // active"); one held high keeps its latch, across an IF=0 stretch too
        // (the STI-shadow case: latched with IF=1, still pending after CLI).
        // ---------------------------------------------------------------------
        $display("");
        $display("[D] INTR withdrawn before the boundary:");
        apply_reset();
        iflag = 1'b1;
        intr = 1'b1;
        tick();
        check(intr_pending === 1'b1, "INTR high with IF=1 latches the request");
        iflag = 1'b0;
        tick();
        check(intr_pending === 1'b1, "a held request stays latched while IF=0");
        check(interrupt_pending === 1'b0, "IF=0 masks the held request");
        intr = 1'b0;
        tick();
        check(intr_pending === 1'b0, "INTR withdrawn: the latch clears");
        iflag = 1'b1;
        tick();
        check(interrupt_pending === 1'b0, "IF=1 again: nothing to deliver");

        // ---------------------------------------------------------------------
        // Verdict.
        // ---------------------------------------------------------------------
        $display("");
        $display("========================================");
        if (errors != 0) begin
            $display("  TB_INTERRUPT_NMI: FAIL (%0d failed checks)", errors);
            $fatal(1, "TB_INTERRUPT_NMI: FAIL");
        end else if (nested_window === 1'b0 && post_iret_window === 1'b1 &&
                 nested_control === 1'b0 && post_iret_control === 1'b0 &&
                 blocked_edge_latched === 1'b1)
            $display("  TB_INTERRUPT_NMI: PASS - window and in-handler edges deferred, delivered only after IRET");
        else begin
            $display("  TB_INTERRUPT_NMI: FAIL - unexpected NMI dispatch sequence");
            $fatal(1, "TB_INTERRUPT_NMI: FAIL");
        end
        $display("========================================");
        $finish;
    end

    // Bound the run.
    initial begin
        #100000;
        $fatal(1, "TB_INTERRUPT_NMI: TIMEOUT");
    end

endmodule
