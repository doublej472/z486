//
// Interrupt Latches
// Architectural interrupt latches and the STI/MOV SS interrupt shadow
//
module interrupt_controller
    import z486_pkg::*;
(
    input  logic       clk,
    input  logic       reset_n,
    input  logic       intr,
    input  logic       nmi,
    input  logic       iflag,
    input  logic       i_rni,
    input  logic       shadow_start,
    input  logic       shadow_ss,      // shadow_start is a MOV SS / POP SS
    input  logic       uc_exec,
    input  logic [6:0] uc_aluop,
    input  logic       nmi_accept_boundary,
    output logic       intr_pending,
    output logic       nmi_request_active,
    output logic       interrupt_pending,
    output logic       inhibit_interrupts
);

logic intr_latch_inhibit;
logic nmi_pending;
logic nmi_blocked;
logic nmi_prev;
logic nmi_ss_shadow;

// MOV SS / POP SS hold NMI to the boundary after the next instruction; STI's
// shadow holds INTR only. Intel486 PRM (1992) 9.3.4, p. 9-5: "the Intel486
// processor inhibits interrupts, debug exceptions, and single-step trap
// exceptions after either a MOV to SS instruction or a POP to SS instruction,
// until the instruction boundary following the next instruction is reached."
// POP, p. 26-231: "A POP SS instruction inhibits all interrupts, including
// NMI, until after execution of the next instruction." STI, p. 26-271: "The
// processor then responds to external interrupts after executing the next
// instruction" (IF governs INTR only, 9.3.2). The edge still latches in
// nmi_pending (no accept while the shadow holds it), and interrupt_pending
// keeps the ungated request so a shadowed HLT or REP string still sees it.
wire nmi_request_raw;

wire nmi_edge = nmi && !nmi_prev;

// nmi_blocked (SETNMI at handler entry, CLRNMI at IRET) gates delivery, not
// the latch: an edge while it is set is held in nmi_pending and delivered
// after CLRNMI. Intel486 DX data sheet (Oct 1992) 2.7.4, p. 46: "If NMI
// occurs while currently servicing an NMI, its presence will be saved for
// servicing after executing the first IRET instruction." (Embedded Intel486
// Processor Family Developer's Manual 3.15.4, the same words.)
assign nmi_request_raw    = !nmi_blocked && (nmi_pending || nmi_edge);
assign nmi_request_active = nmi_request_raw && !nmi_ss_shadow;
assign interrupt_pending = nmi_request_raw || (intr_pending && iflag);

always_ff @(posedge clk) begin
    if (!reset_n) begin
        nmi_prev             <= 1'b0;
        nmi_pending          <= 1'b0;
        nmi_blocked          <= 1'b0;
        intr_pending         <= 1'b0;
        intr_latch_inhibit   <= 1'b0;
        inhibit_interrupts   <= 1'b0;
        nmi_ss_shadow        <= 1'b0;
    end else begin
        nmi_prev <= nmi;
        // Single-cycle event discipline for the NMI latch: writing the set and
        // the accept-clear as two NBAs whose guard is `nmi_edge &&
        // !nmi_accept_boundary` eats an NMI edge landing in the accept cycle
        // whenever the boundary is consuming a DIFFERENT request (an older
        // pending NMI, or a stolen boundary): the edge is neither latched nor
        // re-queued. One folded next-state instead - the accept consumes EXACTLY
        // ONE request: the pending latch if it has one, in which case a
        // same-cycle edge is a NEW event and is deferred (set wins over the
        // clear, never eaten); or the same-cycle edge itself when the latch is
        // empty, which the combinational `nmi_request_active` path has already
        // delivered to this very accept (re-latching it would deliver one NMI
        // edge TWICE).
        nmi_pending <= nmi_accept_boundary ? (nmi_pending & nmi_edge)
                                           : (nmi_pending | nmi_edge);

        // INTR is level-sensitive. CINTLA (between the two INTA cycles)
        // suppresses re-latching the request being acknowledged, whose INTR the
        // PIC drops only after the second INTA. The re-arm is the request's
        // deassertion OR the next instruction boundary (the end of the
        // delivery, long after the second INTA has completed): a 486 samples
        // INTR as a level at each boundary and does not require it to go low
        // between two requests. A re-arm on the deassertion alone wedges when
        // the PIC raises INTR again for a higher-priority request at, or within
        // one CPU clock of, the acknowledge - the low phase is never sampled
        // (always so under a gated CPU clock whose skipped edges hide it), and
        // INTR then stays high with IF=1 and is never taken again. While IF is
        // clear nothing latches, so for an interrupt gate (or real mode) the
        // boundary re-arm changes nothing until IRET/STI sets IF.
        //
        // The latch is the request's LEVEL, not an event: it holds only while
        // INTR stays high, so a request the device withdraws before the
        // boundary (an 8259 whose IRQ was masked through OCW1, or whose line
        // fell) is not acknowledged. Intel486 DX data sheet (Oct 1992) 6.4.1:
        // "The INTR Signal is level sensitive and must remain active for the
        // instruction execution unit to recognize it: The interrupt will not
        // be serviced by the Intel486 Microprocessor if the INTR signal does
        // not remain active." While INTR stays high the next state is the old
        // sticky set (intr_pending implies !intr_latch_inhibit: the latch is
        // set only while the inhibit is clear, and CINTLA clears the latch in
        // the cycle it sets the inhibit), so recognising a held request takes
        // exactly the cycles it did; only a withdrawn one changes, cleared on
        // the first clock that samples INTR low.
        if (!intr || i_rni)
            intr_latch_inhibit <= 1'b0;
        intr_pending <= intr && (intr_pending || (iflag && !intr_latch_inhibit));

        if (shadow_start)
            inhibit_interrupts <= 1'b1;
        else if (i_rni && inhibit_interrupts)
            inhibit_interrupts <= 1'b0;
        // Same set/clear points as inhibit_interrupts (shadow_start implies
        // i_rni), so an STI that follows MOV SS ends the NMI hold on time.
        if (i_rni)
            nmi_ss_shadow <= shadow_start && shadow_ss;

        if (uc_exec) begin
            case (uc_aluop)
                ALUJMP_CLRNMI: nmi_blocked <= 1'b0;
                ALUJMP_SETNMI: nmi_blocked <= 1'b1;
                ALUJMP_CINTLA: begin
                    intr_pending       <= 1'b0;
                    intr_latch_inhibit <= 1'b1;
                end
                default: ;
            endcase
        end
    end
end

// synthesis translate_off
// The invariant the held-request equivalence above rests on.
always @(posedge clk)
    if (reset_n && intr_pending && intr_latch_inhibit)
        $fatal(1, "interrupt_controller: intr_pending set while the CINTLA inhibit is active");
// synthesis translate_on

endmodule
