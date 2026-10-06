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
// Unclassified dead slots: why port B's registered eligibility said no.
//   0 eligible but late terms failed   1 multi-uStep predecessor, not qualified
//   2 successor not taken from D1 at the predecessor's issue
//   3 successor class not B1-eligible  4 successor unsafe (flags/EA/hazard)
//   5 eligible-from-issue but other     6 predecessor issue not hardwired/shape
longint m0_unclass [0:6];
longint m0_unsafe [0:3];
// A direct load's first word (a dead slot) left unused:
//   0 total  1 no D2 instruction  2 D2 payload incomplete  3 EA interlock on a
//   pending load  4 eligibility register low  5 D2 not ready  6 issued late terms
//   (pb_load_ready/throttle/interrupt)  7 other
longint m0_ldslot [0:7];
// ...eligibility low, by the term at the load's issue: 0 successor not taken
// from D1  1 class  2 unsafe  3 M3 ALU-result read  4 POP ESP base  5 RET  6 other
longint m0_ldelig [0:6];
logic   m0_iss_aluconf, m0_iss_popesp, m0_iss_ret;
logic [8:0] m0_iss_nextop;              // {has_0f, opcode} of the successor at issue
longint m0_ldclass_op [0:511];
logic   m0_iss_nexthw;
longint m0_ldclass_nothw;
// Cycles spent in ESC (x87) routines, by executing microcode address.
longint m0_esc_uc [0:4095];
longint m0_esc_uc_mem [0:4095];
longint m0_esc_total, m0_esc_xbusy;
logic   m0_x87_busy;
generate
    if (ENABLE_X87) begin : gen_m0_x87
        assign m0_x87_busy = dut.x87.gen_x87.control.executor.busy;
    end else begin : gen_m0_nox87
        assign m0_x87_busy = 1'b0;
    end
endgenerate   // flags, EA vs predecessor, pending load commit, pending shift
logic [3:0] m0_iss_unsafe;
logic   m0_iss_pbload, m0_iss_type, m0_iss_safe, m0_iss_shape;
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
    for (integer i = 0; i < 7; i++) m0_unclass[i] = 0;
    for (integer i = 0; i < 4; i++) m0_unsafe[i] = 0;
    for (integer i = 0; i < 8; i++) m0_ldslot[i] = 0;
    for (integer i = 0; i < 7; i++) m0_ldelig[i] = 0;
    for (integer i = 0; i < 512; i++) m0_ldclass_op[i] = 0;
    m0_ldclass_nothw = 0;
    for (integer i = 0; i < 4096; i++) begin m0_esc_uc[i] = 0; m0_esc_uc_mem[i] = 0; end
    m0_esc_total = 0; m0_esc_xbusy = 0;
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

        if (dut.data_access_inst.vipt_issue_load)                         m0_mempath[0] += 1;
        if (dut.data_access_inst.vipt_replay_try)                         m0_mempath[1] += 1;
        if (dut.vipt_slow_submit)                        m0_mempath[2] += 1;
        if (dut.data_access_inst.rd_fast_issue)                           m0_mempath[3] += 1;
        if (dut.data_access_inst.fast_store_accepted)                     m0_mempath[4] += 1;
        if (dut.data_access_inst.ucrd_take)                               m0_mempath[5] += 1;
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
        if (dut.i_issue) begin
            m0_iss_pbload = dut.hardwired_control_inst.pb_load;
            m0_iss_type   = dut.hardwired_control_inst.pbn_type;
            m0_iss_safe   = dut.hardwired_control_inst.pbn_safe;
            m0_iss_aluconf = dut.hardwired_control_inst.pbn_load_alu_conf;
            m0_iss_popesp = dut.hardwired_control_inst.load_pipe_pop &&
                (dut.hardwired_control_inst.pb_next_ea.base_sel[4] ||
                 dut.hardwired_control_inst.pb_next_ea.index_sel[4]);
            m0_iss_ret = dut.hardwired_control_inst.load_pipe_ret;
            m0_iss_nextop = {dut.hardwired_control_inst.pb_next_instr.has_0f,
                             dut.hardwired_control_inst.pb_next_instr.opcode};
            m0_iss_nexthw = dut.hardwired_control_inst.pbn_recipe.hardwired;
            m0_iss_unsafe[0] = dut.hardwired_control_inst.pbn_recipe.reads_flags &&
                               dut.hardwired_control_inst.issue_recipe.writes_flags &&
                               !dut.hardwired_control_inst.pbn_recipe.jcc;
            m0_iss_unsafe[1] = dut.hardwired_control_inst.pbn_recipe.uses_ea &&
                dut.hardwired_control_inst.ea_conflict(dut.hardwired_control_inst.pred1_we,
                    dut.hardwired_control_inst.pred1_widx, dut.hardwired_control_inst.pb_next_ea,
                    dut.hardwired_control_inst.pb_next_instr,
                    dut.hardwired_control_inst.issue_recipe.commit_sel == z486_pkg::RECIPE_COMMIT_ESP);
            m0_iss_unsafe[2] = dut.hardwired_control_inst.mem_hazard &&
                (dut.hardwired_control_inst.pb_next_ea.base_sel[dut.hardwired_control_inst.mem_widx] ||
                 dut.hardwired_control_inst.pb_next_ea.index_sel[dut.hardwired_control_inst.mem_widx] ||
                 dut.hardwired_control_inst.pbn_read_mask[dut.hardwired_control_inst.mem_widx]);
            m0_iss_unsafe[3] = dut.hardwired_control_inst.shift_hazard &&
                (dut.hardwired_control_inst.pb_next_ea.base_sel[dut.hardwired_control_inst.shift_widx] ||
                 dut.hardwired_control_inst.pb_next_ea.index_sel[dut.hardwired_control_inst.shift_widx] ||
                 dut.hardwired_control_inst.pbn_read_mask[dut.hardwired_control_inst.shift_widx]);
            m0_iss_shape  = dut.hardwired_control_inst.issue_hardwired &&
                ((!dut.hardwired_control_inst.issue_recipe.multi_ustep &&
                  !dut.hardwired_control_inst.issue_recipe.jcc) ||
                 dut.hardwired_control_inst.issue_recipe.jcc);
        end
        if ((dut.i.opcode[7:3] == 5'b11011) && !dut.i.has_0f && dut.uc_active) begin
            m0_esc_total += 1;
            m0_esc_uc[dut.uc_addr] += 1;
            if (dut.stall_mem) m0_esc_uc_mem[dut.uc_addr] += 1;
            if (m0_x87_busy) m0_esc_xbusy += 1;
        end
        if (dut.hardwired_control_inst.pb_load_slot_r && !dut.i_issue && !dut.stall &&
            !dut.q_flush) begin
            m0_ldslot[0] += 1;
            if (!dut.pb_valid)                                m0_ldslot[1] += 1;
            else if (!dut.d2_push)                            m0_ldslot[2] += 1;
            else if (dut.d2_vipt_ea_hazard)                   m0_ldslot[3] += 1;
            else if (!dut.hardwired_control_inst.pb_b1_ok_r) begin
                m0_ldslot[4] += 1;
                if (!m0_iss_pbload)        m0_ldelig[0] += 1;
                else if (!m0_iss_type) begin
                    m0_ldelig[1] += 1;
                    m0_ldclass_op[m0_iss_nextop] += 1;
                    if (!m0_iss_nexthw) m0_ldclass_nothw += 1;
                end
                else if (!m0_iss_safe)     m0_ldelig[2] += 1;
                else if (m0_iss_aluconf)   m0_ldelig[3] += 1;
                else if (m0_iss_popesp)    m0_ldelig[4] += 1;
                else if (m0_iss_ret)       m0_ldelig[5] += 1;
                else                       m0_ldelig[6] += 1;
            end
            else if (!dut.d2_ready)                           m0_ldslot[5] += 1;
            else if (!dut.pb_load_ready || dut.throttle_hold ||
                     dut.interrupt_pending)                   m0_ldslot[6] += 1;
            else                                              m0_ldslot[7] += 1;
        end
        if (m0_dead_hardwired_slot) begin
            m0_chain_block[0] += 1;
            if (dut.q_flush)
                chain_reason = 10;
            else if (dut.interrupt_pending || dut.tf_active_r ||
                     dut.data_access_inst.single_step || dut.any_fault_issue ||
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
            if (chain_reason == 11) begin
                if (dut.hardwired_control_inst.pb_b1_ok_r)      m0_unclass[0] += 1;
                else if (dut.hardwired_control_inst.recipe_state.multi_ustep) m0_unclass[1] += 1;
                else if (!m0_iss_shape)                         m0_unclass[6] += 1;
                else if (!m0_iss_pbload)                        m0_unclass[2] += 1;
                else if (!m0_iss_type)                          m0_unclass[3] += 1;
                else if (!m0_iss_safe) begin
                    m0_unclass[4] += 1;
                    for (int k = 0; k < 4; k++) if (m0_iss_unsafe[k]) m0_unsafe[k] += 1;
                end
                else                                            m0_unclass[5] += 1;
            end
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

// TLB port and sidecar audit (+profile_m0), counted only while paging is on.
// M0_TLBPORT: 0 cycles  1 paging-on cycles  2 prefetch wants a translation
// (paging idle)  3 prefetch translated in one cycle  4 registered port held
// another page (capture bubble)  5 ...displaced by a demand capture
// 6 demand and prefetch want the registered port in the same cycle
// 7 prefetch waiting while paging serves demand  8 live-port lookups
// 9 ...I/O  10 ...memory  11-12 unused (the live port is gone)
// 13 prefetch walks  14 demand walks  15 walk cycles  16 INVLPG  17 CR3 writes
// 18 cycles a direct probe or store route needs a translation  19 ...and
// prefetch wants one too  20 cycles with two or more translation needs
// M0_SIDECAR: per consumer (0 direct-load/RMW/ucode-read probe, 1 store
// route) {events, hit, hazard-poisoned, miss held by the main TLB}.
// M0_SHADOW <cfg> <sets> <ways> <lookups> <hits>: standalone LRU TLBs that
// fill on every miss. Configs 0-3 see the sidecar stream (direct probes and
// store routes); 4-7 see every translation (sidecar stream, memory live
// lookups, prefetch page changes), i.e. one unified i486-style TLB.
localparam integer M0_NSH = 8;
localparam integer M0_SH_SETS [M0_NSH] = '{32, 64, 128, 256, 8, 16, 8, 16};
localparam integer M0_SH_WAYS [M0_NSH] = '{1, 1, 1, 1, 4, 4, 8, 8};
longint m0_tlbport [0:20];
longint m0_sidecar [0:1][0:3];
longint m0_shadow_lookups [M0_NSH];
longint m0_shadow_hits [M0_NSH];
logic [19:0] m0_sh_tag [M0_NSH][0:255][0:7];
logic        m0_sh_v   [M0_NSH][0:255][0:7];
longint      m0_sh_age [M0_NSH][0:255][0:7];
logic   m0_lookup_by_demand;
logic   m0_probe_prev;
logic [19:0] m0_pf_last_vpn;

function automatic logic m0_main_tlb_has(input logic [19:0] vpn);
    logic [2:0]  set;
    logic [16:0] tag;
    set = vpn[2:0];
    tag = vpn[19:3];
    m0_main_tlb_has =
        (dut.paging_inst.tlb_inst.valid_q[set][0] && dut.paging_inst.tlb_inst.lookup_copy0[set][36:20] == tag) ||
        (dut.paging_inst.tlb_inst.valid_q[set][1] && dut.paging_inst.tlb_inst.lookup_copy1[set][36:20] == tag) ||
        (dut.paging_inst.tlb_inst.valid_q[set][2] && dut.paging_inst.tlb_inst.lookup_copy2[set][36:20] == tag) ||
        (dut.paging_inst.tlb_inst.valid_q[set][3] && dut.paging_inst.tlb_inst.lookup_copy3[set][36:20] == tag);
endfunction

// One LRU lookup in shadow config c; a miss fills the oldest way.
task automatic m0_shadow_access(input integer c, input logic [19:0] vpn);
    integer set, victim;
    logic hit;
    set = vpn % M0_SH_SETS[c];
    hit = 1'b0;
    victim = 0;
    m0_shadow_lookups[c] += 1;
    for (integer w = 0; w < M0_SH_WAYS[c]; w++)
        if (m0_sh_v[c][set][w] && m0_sh_tag[c][set][w] == vpn) begin
            hit = 1'b1;
            m0_sh_age[c][set][w] = cycle;
        end
    if (hit) begin
        m0_shadow_hits[c] += 1;
    end else begin
        for (integer w = 1; w < M0_SH_WAYS[c]; w++)
            if (!m0_sh_v[c][set][w] ||
                (m0_sh_v[c][set][victim] && m0_sh_age[c][set][w] < m0_sh_age[c][set][victim]))
                victim = w;
        m0_sh_v[c][set][victim] = 1'b1;
        m0_sh_tag[c][set][victim] = vpn;
        m0_sh_age[c][set][victim] = cycle;
    end
endtask

task automatic m0_shadow_flush(input logic all, input logic [19:0] vpn);
    for (integer c = 0; c < M0_NSH; c++)
        for (integer i = 0; i < 256; i++)
            for (integer w = 0; w < 8; w++)
                if (all || m0_sh_tag[c][i][w] == vpn) m0_sh_v[c][i][w] = 1'b0;
endtask

task automatic m0_sidecar_consume(input integer site, input logic [19:0] vpn);
    m0_sidecar[site][0] += 1;
    if (dut.paging_inst.tlb_inst.vipt_match) m0_sidecar[site][1] += 1;
    if (dut.paging_inst.tlb_inst.vipt_hazard_r) m0_sidecar[site][2] += 1;
    if (!dut.paging_inst.tlb_inst.vipt_match && m0_main_tlb_has(vpn)) m0_sidecar[site][3] += 1;
    for (integer c = 0; c < M0_NSH; c++) m0_shadow_access(c, vpn);
endtask

always @(posedge clk) begin : m0_tlb_sample
    if (!reset_n) begin
        m0_lookup_by_demand = 1'b0;
        m0_probe_prev = 1'b0;
        m0_pf_last_vpn = 20'hfffff;
        m0_shadow_flush(1'b1, 20'd0);
    end else if ($test$plusargs("profile_m0")) begin
        m0_tlbport[0] += 1;
        if (dut.paging_inst.cr3_write) m0_shadow_flush(1'b1, 20'd0);
        if (dut.paging_inst.invlpg_fire) m0_shadow_flush(1'b0, dut.paging_inst.invlpg_linear[31:12]);
        if (dut.paging_inst.pg_enable) begin
            m0_tlbport[1] += 1;
            if (dut.paging_inst.idle_pf_req) m0_tlbport[2] += 1;
            if (dut.paging_inst.fast_pf_candidate) m0_tlbport[3] += 1;
            if (dut.paging_inst.idle_pf_req && !dut.paging_inst.pf_tlb_match) begin
                m0_tlbport[4] += 1;
                if (m0_lookup_by_demand) m0_tlbport[5] += 1;
            end
            if (dut.paging_inst.idle_mem_precheck_capture && dut.paging_inst.pf_pending)
                m0_tlbport[6] += 1;
            if (dut.paging_inst.pf_pending && !dut.paging_inst.s_idle) m0_tlbport[7] += 1;
            if (dut.paging_inst.idle_data_req) begin
                m0_tlbport[8] += 1;
                if (dut.paging_inst.mem_is_io) m0_tlbport[9] += 1;
                else if (dut.paging_inst.live_valid) begin
                    m0_tlbport[10] += 1;
                    for (integer c = 4; c < M0_NSH; c++)
                        m0_shadow_access(c, dut.paging_inst.linear_addr[31:12]);
                end
            end
            if (dut.paging_inst.idle_pf_req &&
                dut.paging_inst.pf_linear_addr[31:12] != m0_pf_last_vpn) begin
                m0_pf_last_vpn = dut.paging_inst.pf_linear_addr[31:12];
                for (integer c = 4; c < M0_NSH; c++) m0_shadow_access(c, m0_pf_last_vpn);
            end
            if (dut.paging_inst.tlb_update_valid) begin
                if (dut.paging_inst.state == 4'd10) m0_tlbport[13] += 1;
                else m0_tlbport[14] += 1;
            end
            if (dut.paging_inst.state == 4'd2 || dut.paging_inst.state == 4'd7 ||
                dut.paging_inst.state == 4'd10)
                m0_tlbport[15] += 1;
            begin
                integer needs;
                logic direct;
                direct = dut.dcache_vipt_probe_valid || dut.data_access_inst.st_route_pre;
                needs = direct + dut.paging_inst.idle_pf_req +
                        (dut.paging_inst.idle_data_req && !dut.paging_inst.mem_is_io);
                if (direct) m0_tlbport[18] += 1;
                if (direct && dut.paging_inst.idle_pf_req) m0_tlbport[19] += 1;
                if (needs >= 2) m0_tlbport[20] += 1;
            end
            // A probe's preread resolves in the next cycle against vipt_linear_r.
            if (m0_probe_prev)
                m0_sidecar_consume(0, dut.paging_inst.tlb_inst.vipt_linear_r[31:12]);
            if (dut.data_access_inst.st_route_pre)
                m0_sidecar_consume(1, dut.paging_inst.tlb_inst.vipt_linear_r[31:12]);
        end
        if (dut.paging_inst.invlpg_fire) m0_tlbport[16] += 1;
        if (dut.paging_inst.cr3_write) m0_tlbport[17] += 1;
        if (dut.paging_inst.idle_mem_precheck_capture) m0_lookup_by_demand = 1'b1;
        else if (dut.paging_inst.idle_pf_lookup_capture) m0_lookup_by_demand = 1'b0;
        m0_probe_prev = dut.dcache_vipt_probe_valid;
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
        for (integer i = 0; i < 7; i++)
            $display("M0_UNCLASS %0d %0d", i, m0_unclass[i]);
        for (integer i = 0; i < 4; i++)
            $display("M0_UNSAFE %0d %0d", i, m0_unsafe[i]);
        for (integer i = 0; i < 8; i++)
            $display("M0_LDSLOT %0d %0d", i, m0_ldslot[i]);
        for (integer i = 0; i < 7; i++)
            $display("M0_LDELIG %0d %0d", i, m0_ldelig[i]);
        $display("M0_LDCLASS_NOTHW %0d", m0_ldclass_nothw);
        for (integer i = 0; i < 21; i++)
            $display("M0_TLBPORT %0d %0d", i, m0_tlbport[i]);
        for (integer i = 0; i < 2; i++)
            $display("M0_SIDECAR %0d %0d %0d %0d %0d", i, m0_sidecar[i][0],
                     m0_sidecar[i][1], m0_sidecar[i][2], m0_sidecar[i][3]);
        for (integer i = 0; i < M0_NSH; i++)
            $display("M0_SHADOW %0d %0d %0d %0d %0d", i, M0_SH_SETS[i], M0_SH_WAYS[i],
                     m0_shadow_lookups[i], m0_shadow_hits[i]);
        $display("M0_ESC_TOTAL %0d executor_busy %0d", m0_esc_total, m0_esc_xbusy);
        for (integer i = 0; i < 4096; i++)
            if (m0_esc_uc[i] > 20000)
                $display("M0_ESC_UC %03x %0d mem %0d", i, m0_esc_uc[i], m0_esc_uc_mem[i]);
        for (integer i = 0; i < 512; i++)
            if (m0_ldclass_op[i] > 200) $display("M0_LDCLASS_OP %03x %0d", i, m0_ldclass_op[i]);
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
