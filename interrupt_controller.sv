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

wire nmi_edge = nmi && !nmi_prev && !nmi_blocked;

// nmi_blocked also gates the pending latch: a window edge stays queued and is
// delivered only after CLRNMI (post-IRET).
assign nmi_request_active = (nmi_pending && !nmi_blocked) || nmi_edge;
assign interrupt_pending = nmi_request_active || (intr_pending && iflag);

always_ff @(posedge clk) begin
    if (!reset_n) begin
        nmi_prev             <= 1'b0;
        nmi_pending          <= 1'b0;
        nmi_blocked          <= 1'b0;
        intr_pending         <= 1'b0;
        intr_latch_inhibit   <= 1'b0;
        inhibit_interrupts   <= 1'b0;
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

        // INTR is level-sensitive. CINTLA suppresses re-latching until the
        // external request is deasserted.
        if (!intr)
            intr_latch_inhibit <= 1'b0;
        if (intr && iflag && !intr_latch_inhibit)
            intr_pending <= 1'b1;

        if (shadow_start)
            inhibit_interrupts <= 1'b1;
        else if (i_rni && inhibit_interrupts)
            inhibit_interrupts <= 1'b0;

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

endmodule
