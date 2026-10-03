// M0 sustained-delivery profiler.  This file is included inside testbenches
// that instantiate the current core as `dut` and expose `clk`, `reset_n`, and
// `cycle`.  All state is simulation-only and enabled by +profile_m0.

longint m0_chain_block [0:11];
longint m0_supply_block [0:8];
longint m0_interval [0:7][0:16];
longint m0_pf_occupancy [0:32];
longint m0_decq_occupancy [0:2];
longint m0_starve_burst [0:8];
longint m0_frontend_event_count [0:5];
longint m0_frontend_event_sum [0:5];
longint m0_frontend_event_max [0:5];
longint m0_supply_control [0:5];
longint m0_supply_length [0:15];
longint m0_supply_crossing [0:1];
longint m0_supply_demand [0:1];
// Data-access routes into the D-cache, one count per accepted access:
// 0 VIPT direct load issue, 1 VIPT replay probe, 2 VIPT slow (paging) submit,
// 3 RD_FAST RMW issue, 4 WR_FAST store, 5 paging early read, 6 paging early
// write, 7 paging PG_MEM_TLB access, 8 stall_mem cycles, 9 dcache_req refused.
longint m0_mempath [0:9];
// Dead slots whose successor was decoded but not loaded into D2 (chain
// reason 2), split by what kept it from issuing in this cycle:
// 0 D2 complete, no split EA: a decoded first uStep would issue it now (M2);
// 1 D2 complete but a base+index+disp EA still needs its D2a cycle;
// 2 successor in the skeleton, literals still being captured;
// 3 successor still in D1 (direct D1 issue only): decoder latency (M1).
longint m0_d2late [0:3];
// Of bucket 0: the successor is a hardwired recipe that passes the chain
// hazard rules (head_issue_safe), so it could take the dead slot directly.
longint m0_d2late_safe;
// Port B's word selected for EX (pb_slot) on an edge that issued nothing.
longint m0_pb_slot_noissue;
// Bucket 0 split by the successor's recipe early kind (0 = not hardwired).
longint m0_d2late_kind [0:7];

logic        m0_have_previous;
longint      m0_previous_issue_cycle;
logic [31:0] m0_previous_eip;
logic [4:0]  m0_previous_length;
logic [11:0] m0_previous_entry;
logic [2:0]  m0_previous_control;
logic        m0_previous_crossing;
logic        m0_after_flush;
logic        m0_starving;
longint      m0_starve_start;
logic [5:0]  m0_frontend_event_seen;

wire m0_dead_hardwired_slot =
    dut.hardwired_control_inst.recipe_rni && dut.uc_exec && !dut.i_issue &&
    !dut.hardwired_control_inst.recipe_state.slot_has_work;
wire m0_instruction_supply_blocked =
    !dut.stall && !dut.throttle_hold &&
    (dut.decoder_fetch_blocked ||
     ((!dut.uc_active || m0_dead_hardwired_slot) && !dut.pb_valid &&
      dut.decq_empty));
wire m0_pf_request_launched = dut.prefetch_inst.spec_launch ||
                              dut.prefetch_inst.pf_can_fetch_after_flush ||
                              dut.prefetch_inst.pf_can_fetch;
wire [5:0] m0_pf_bytes = dut.prefetch_inst.pf_byte_count;
wire [1:0] m0_decq_depth = {1'b0, dut.decoder_inst.skel_v};

function automatic integer m0_interval_bin(input longint value);
    m0_interval_bin = value >= 16 ? 16 : value;
endfunction

function automatic integer m0_burst_bin(input longint value);
    if (value <= 1)       m0_burst_bin = 0;
    else if (value == 2)  m0_burst_bin = 1;
    else if (value == 3)  m0_burst_bin = 2;
    else if (value == 4)  m0_burst_bin = 3;
    else if (value <= 7)  m0_burst_bin = 4;
    else if (value <= 15) m0_burst_bin = 5;
    else if (value <= 31) m0_burst_bin = 6;
    else if (value <= 63) m0_burst_bin = 7;
    else                  m0_burst_bin = 8;
endfunction

task automatic m0_record_frontend_event(input integer event_index);
    longint delta;
    begin
        if (m0_starving && !m0_frontend_event_seen[event_index]) begin
            delta = cycle - m0_starve_start;
            m0_frontend_event_seen[event_index] = 1'b1;
            m0_frontend_event_count[event_index] += 1;
            m0_frontend_event_sum[event_index] += delta;
            if (delta > m0_frontend_event_max[event_index])
                m0_frontend_event_max[event_index] = delta;
        end
    end
endtask

initial begin : m0_profile_init
    for (integer i = 0; i < 12; i++) m0_chain_block[i] = 0;
    for (integer i = 0; i < 9; i++) begin
        m0_supply_block[i] = 0;
        m0_starve_burst[i] = 0;
    end
    for (integer i = 0; i < 8; i++)
        for (integer j = 0; j < 17; j++) m0_interval[i][j] = 0;
    for (integer i = 0; i < 33; i++) m0_pf_occupancy[i] = 0;
    for (integer i = 0; i < 3; i++) m0_decq_occupancy[i] = 0;
    for (integer i = 0; i < 6; i++) begin
        m0_frontend_event_count[i] = 0;
        m0_frontend_event_sum[i] = 0;
        m0_frontend_event_max[i] = 0;
        m0_supply_control[i] = 0;
    end
    for (integer i = 0; i < 16; i++) m0_supply_length[i] = 0;
    for (integer i = 0; i < 2; i++) begin
        m0_supply_crossing[i] = 0;
        m0_supply_demand[i] = 0;
    end
    for (integer i = 0; i < 10; i++) m0_mempath[i] = 0;
    for (integer i = 0; i < 4; i++) m0_d2late[i] = 0;
    m0_d2late_safe = 0;
    m0_pb_slot_noissue = 0;
    for (integer i = 0; i < 8; i++) m0_d2late_kind[i] = 0;
    m0_have_previous = 1'b0;
    m0_previous_control = 3'd0;
    m0_previous_crossing = 1'b0;
    m0_after_flush = 1'b0;
    m0_starving = 1'b0;
    m0_frontend_event_seen = 6'b0;
end

always @(posedge clk) begin : m0_profile_sample
    integer interval;
    integer control_class;
    integer supply_reason;
    integer chain_reason;
    integer burst_bin;
    longint burst_length;

    if (!reset_n) begin
        m0_have_previous = 1'b0;
        m0_after_flush = 1'b0;
        m0_starving = 1'b0;
        m0_frontend_event_seen = 6'b0;
    end else if ($test$plusargs("profile_m0")) begin
        m0_pf_occupancy[m0_pf_bytes > 32 ? 32 : m0_pf_bytes] += 1;
        m0_decq_occupancy[m0_decq_depth > 2 ? 2 : m0_decq_depth] += 1;

        if (dut.q_flush)
            m0_after_flush = 1'b1;

        if (dut.vipt_issue_load)                         m0_mempath[0] += 1;
        if (dut.vipt_replay_try)                         m0_mempath[1] += 1;
        if (dut.vipt_slow_submit)                        m0_mempath[2] += 1;
        if (dut.rd_fast_issue)                           m0_mempath[3] += 1;
        if (dut.fast_store_accepted)                     m0_mempath[4] += 1;
        if (dut.paging_inst.early_rd_accept)             m0_mempath[5] += 1;
        if (dut.paging_inst.early_wr_accept)             m0_mempath[6] += 1;
        if (dut.paging_inst.req_mem_dcache_accept)       m0_mempath[7] += 1;
        if (dut.stall_mem)                               m0_mempath[8] += 1;
        if (dut.pb_slot && !dut.i_issue && !dut.stall)   m0_pb_slot_noissue += 1;
        if (dut.paging_inst.dcache_req_valid && !dut.paging_inst.dcache_req_accepted)
                                                         m0_mempath[9] += 1;

        // Issue-to-issue intervals.  Control-transfer classes are exclusive;
        // load and store successor boundaries are additional orthogonal rows.
        if (dut.i_issue) begin
            if (m0_have_previous) begin
                interval = m0_interval_bin(cycle - m0_previous_issue_cycle);
                if (m0_previous_control == 3'd1) begin
                    if (dut.EIP == (m0_previous_eip + m0_previous_length))
                        m0_interval[1][interval] += 1; // Jcc fall-through
                    else
                        m0_interval[2][interval] += 1; // Jcc taken target
                end else if (m0_previous_control == 3'd2) begin
                    m0_interval[3][interval] += 1;     // JMP target
                end else if (m0_previous_control == 3'd3) begin
                    m0_interval[4][interval] += 1;     // CALL target
                end else if (m0_previous_control == 3'd4) begin
                    m0_interval[5][interval] += 1;     // RET target
                end else begin
                    m0_interval[0][interval] += 1;     // straight-line
                end
                if (m0_previous_entry == 12'h019)
                    m0_interval[6][interval] += 1;
                if (m0_previous_entry == 12'h013)
                    m0_interval[7][interval] += 1;
            end

            m0_previous_issue_cycle = cycle;
            m0_previous_eip = dut.EIP;
            m0_previous_length = dut.i_bus.length;
            m0_previous_entry = dut.i_bus.entry_point;
            m0_previous_crossing =
                ({1'b0, dut.EIP[3:0]} + dut.i_bus.length) > 5'd16;
            if (dut.i_bus.rel_branch_kind == 2'd1)
                m0_previous_control = 3'd1;
            else if (dut.i_bus.rel_branch_kind == 2'd2)
                m0_previous_control = 3'd2;
            else if (dut.i_bus.rel_branch_kind == 2'd3)
                m0_previous_control = 3'd3;
            else if ((dut.i_bus.opcode == 8'hC2) ||
                     (dut.i_bus.opcode == 8'hC3))
                m0_previous_control = 3'd4;
            else
                m0_previous_control = 3'd0;
            m0_have_previous = 1'b1;
            m0_after_flush = 1'b0;
        end

        // Every failed hardwired RNI handoff receives exactly one reason.
        if (m0_dead_hardwired_slot) begin
            m0_chain_block[0] += 1;
            if (dut.q_flush)
                chain_reason = 10;
            else if (dut.interrupt_pending || dut.tf_active_r ||
                     dut.single_step || dut.any_fault_issue ||
                     dut.interrupt_entry)
                chain_reason = 9;
            else if (!dut.pb_valid && dut.decoder_fetch_blocked)
                chain_reason = 3;
            else if (!dut.pb_valid && dut.decq_empty)
                chain_reason = 1;
            else if (!dut.pb_valid)
                chain_reason = 2;
            else if (!dut.d2_payload_ready)
                chain_reason = 3;
            else if (dut.hardwired_control_inst.issue_recipe.uses_ea &&
                     dut.hardwired_control_inst.ea2_conflict)
                chain_reason = 5;
            else if ((dut.hardwired_control_inst.issue_recipe.reads_flags &&
                      dut.hardwired_control_inst.recipe_state.writes_flags &&
                      !dut.hardwired_control_inst.issue_recipe.jcc) ||
                     dut.hardwired_control_inst.loaduse_conflict ||
                     dut.hardwired_control_inst.mem_confN ||
                     dut.hardwired_control_inst.shift_confN)
                chain_reason = 4;
            else if (dut.stall_mem || dut.stall_wio ||
                     dut.vipt_load_replay_r.valid || dut.vipt_load_slow_busy ||
                     (dut.d2_vipt_candidate && !dut.d2_vipt_load) ||
                     (dut.d2_vipt_rmw_candidate && !dut.d2_vipt_rmw))
                chain_reason = 7;
            else if (dut.hardwired_control_inst.recipe_state.jcc ||
                     dut.hardwired_control_inst.branch_ustep_rni ||
                     dut.pf_spec_owner_r)
                chain_reason = 8;
            else if (!dut.hardwired_control_inst.issue_recipe.hardwired ||
                     dut.throttle_hold || 1'b0 ||
                     !dut.d2_ready)
                chain_reason = 6;
            else
                chain_reason = 11;
            m0_chain_block[chain_reason] += 1;
            if (chain_reason == 2) begin
                if (dut.decq_empty)
                    m0_d2late[3] += 1;
                else if (!dut.d2_push)
                    m0_d2late[2] += 1;
                else if (dut.d2_entry.ea_complex)
                    m0_d2late[1] += 1;
                else begin
                    m0_d2late[0] += 1;
                    m0_d2late_kind[dut.hardwired_control_inst.issue_recipe.hardwired
                        ? z486_pkg::recipe_early_kind(dut.i_bus.entry_point) : 3'd0] += 1;
                    if (dut.hardwired_control_inst.head_issue_safe)
                        m0_d2late_safe += 1;
                end
            end
        end

        // Count only empty/insufficient frontend states that currently block
        // D1/D2 or a retirement handoff; harmless empty-PF backend time is not
        // included.  Causes are mutually exclusive and ordered by ownership.
        if (m0_instruction_supply_blocked) begin
            m0_supply_block[0] += 1;
            if ((m0_pf_bytes != 0) || (dut.k1q_avail != 0))
                supply_reason = 7;
            else if (dut.q_flush || m0_after_flush)
                supply_reason = 3;
            else if (dut.memory_inst.cache_unit_inst.icache_inst.state == 3'd3)
                supply_reason = 1;
            else if (dut.mem_servicing || dut.mem_req_upcoming ||
                     dut.memory_inst.dcache_mem_valid)
                supply_reason = 2;
            else if (dut.prefetch_inst.pf_ack_edge ||
                     dut.prefetch_inst.good_ack)
                supply_reason = 6;
            else if (dut.prefetch_inst.pf_inflight ||
                     dut.paging_inst.pf_pending)
                supply_reason = 5;
            else if (dut.prefetch_inst.pf_can_fetch ||
                     dut.prefetch_inst.pf_can_fetch_after_flush)
                supply_reason = 4;
            else
                supply_reason = 8;
            m0_supply_block[supply_reason] += 1;

            control_class = m0_after_flush ? 5 : m0_previous_control;
            m0_supply_control[control_class] += 1;
            m0_supply_length[m0_previous_length > 15
                             ? 15 : m0_previous_length] += 1;
            m0_supply_crossing[m0_previous_crossing] += 1;
            m0_supply_demand[dut.mem_servicing || dut.mem_req_upcoming] += 1;

            if (!m0_starving) begin
                m0_starving = 1'b1;
                m0_starve_start = cycle;
                m0_frontend_event_seen = 6'b0;
            end
        end else if (m0_starving) begin
            burst_length = cycle - m0_starve_start;
            burst_bin = m0_burst_bin(burst_length);
            m0_starve_burst[burst_bin] += 1;
            m0_starving = 1'b0;
        end

        if (m0_pf_request_launched)      m0_record_frontend_event(0);
        if (dut.icache_req_accepted)     m0_record_frontend_event(1);
        if (dut.icache_req_complete)     m0_record_frontend_event(2);
        if (dut.prefetch_inst.fill_commit) m0_record_frontend_event(3);
        if (dut.k1p_adv != 0)             m0_record_frontend_event(4);
        if (dut.d2_push)                 m0_record_frontend_event(5);
    end
end

final begin : m0_profile_report
    if ($test$plusargs("profile_m0")) begin
        for (integer i = 0; i < 10; i++)
            $display("M0_MEMPATH %0d %0d", i, m0_mempath[i]);
        for (integer i = 0; i < 4; i++)
            $display("M0_D2LATE %0d %0d", i, m0_d2late[i]);
        $display("M0_D2LATE_SAFE %0d", m0_d2late_safe);
        $display("M0_PB_SLOT_NOISSUE %0d", m0_pb_slot_noissue);
        for (integer i = 0; i < 8; i++)
            $display("M0_D2LATE_KIND %0d %0d", i, m0_d2late_kind[i]);
        for (integer i = 0; i < 12; i++)
            $display("M0_CHAIN %0d %0d", i, m0_chain_block[i]);
        for (integer i = 0; i < 9; i++) begin
            $display("M0_SUPPLY %0d %0d", i, m0_supply_block[i]);
            $display("M0_BURST %0d %0d", i, m0_starve_burst[i]);
        end
        for (integer kind = 0; kind < 8; kind++)
            for (integer bin = 0; bin < 17; bin++)
                if (m0_interval[kind][bin] != 0)
                    $display("M0_INTERVAL %0d %0d %0d", kind, bin,
                             m0_interval[kind][bin]);
        for (integer i = 0; i < 33; i++)
            if (m0_pf_occupancy[i] != 0)
                $display("M0_PF_DEPTH %0d %0d", i, m0_pf_occupancy[i]);
        for (integer i = 0; i < 3; i++)
            $display("M0_DECQ_DEPTH %0d %0d", i, m0_decq_occupancy[i]);
        for (integer i = 0; i < 6; i++) begin
            $display("M0_EVENT %0d %0d %0d %0d", i,
                     m0_frontend_event_count[i], m0_frontend_event_sum[i],
                     m0_frontend_event_max[i]);
            $display("M0_CONTROL %0d %0d", i, m0_supply_control[i]);
        end
        for (integer i = 0; i < 16; i++)
            if (m0_supply_length[i] != 0)
                $display("M0_LENGTH %0d %0d", i, m0_supply_length[i]);
        for (integer i = 0; i < 2; i++) begin
            $display("M0_CROSSING %0d %0d", i, m0_supply_crossing[i]);
            $display("M0_DEMAND %0d %0d", i, m0_supply_demand[i]);
        end
    end
end
