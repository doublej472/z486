//
// TLB for 80386 Paging Unit
// 32-entry 4-way set-associative TLB with pseudo-LRU, plus a 256-entry direct-mapped sidecar TLB
//
`timescale 1ns/1ns
`include "z486_platform.svh"

module paging_tlb
    import z486_pkg::*, z486_cache_map_pkg::*;
#(
    // VGA/device window classified per 4 KB page in the TLB entry; the default
    // reproduces upstream's hardcoded A0000-BFFFF (pfn[19:5] == 5).
    parameter [31:0] VGA_BASE = 32'h000a_0000,
    parameter [31:0] VGA_TOP  = 32'h000b_ffff
)
(
    input               clk,
    input               reset_n,

    // Registered lookup interface (combinational output)
    input        [31:0] linear_addr,
    output reg          hit,
    output reg   [31:0] physical_addr,
    output reg          writable,       // Combined PDE & PTE R/W
    output reg          user,           // Combined PDE & PTE U/S
    output reg          dirty,          // D bit from PTE
    output              is_vga_mem,     // Physical address is in A0000-BFFFF
    output              is_pcd,         // PTE.PCD of the registered lookup's entry

    // Live demand lookup interface. This keeps the idle demand fast path off
    // the registered-address mux used by prefetch/walker lookups.
    input        [31:0] linear_addr_live,
    output reg          live_hit,
    output reg   [31:0] live_physical_addr,
    output reg          live_writable,
    output reg          live_user,
    output reg          live_dirty,
    output              live_is_vga_mem,

    // Side-effect-free D2 preread for hardwired loads. The direct-mapped
    // sidecar is a second TLB lookup port; an EX miss simply falls back to the
    // authoritative four-way TLB and page walker.
    input               vipt_preread,
    input        [31:0] vipt_linear_addr,
    output reg          vipt_hit,
    output reg   [31:0] vipt_physical_addr,
    output reg          vipt_writable,
    output reg          vipt_user,
    output reg          vipt_dirty,
    output              vipt_is_vga_mem,

    // Refill the direct sidecar after a registered demand falls back to an
    // authoritative four-way TLB hit.  This path is intentionally separate
    // from the D2 preread: it cannot feed translation back into D2.
    input               vipt_refill_valid,
    input        [31:0] vipt_refill_linear,
    input        [19:0] vipt_refill_pfn,
    input               vipt_refill_writable,
    input               vipt_refill_user,
    input               vipt_refill_dirty,
    input               vipt_refill_pcd,

    // Update interface (from page walker)
    input               update_valid,
    input        [19:0] update_vpn,     // Virtual page number
    input        [19:0] update_pfn,     // Physical frame number
    input               update_writable,
    input               update_user,
    input               update_dirty,
    input               update_pcd,
    input               update_pwt,     // PTE.PWT, for the TR7 readback only

    // Invalidate all entries (on CR3 write)
    input               invalidate_all,

    // Invalidate every cached translation for one linear page (INVLPG).
    input               invalidate_page,
    input        [19:0] invalidate_vpn,

    // 486 TLB test registers.  A TR6 write (TR6.C = 0) installs an entry
    // from TR6/TR7; with C = 1 it looks one up and reports it through TR7
    // (and the TR6 attribute pairs).  The result pulses tlbt_done.
    input               tlbt_req,
    input        [31:0] tlbt_tr6,
    input        [31:0] tlbt_tr7,
    output reg          tlbt_done,
    output reg          tlbt_lookup_done,
    output reg   [31:0] tlbt_tr6_out,
    output reg   [31:0] tlbt_tr7_out
);

// 8 sets x 4 ways. Tags and PFNs live in MLAB, one copy per read port (the
// registered lookup, the live demand lookup, and INVLPG's tag compare); the
// small per-entry flags, valid bits and PLRU state stay in registers.
// MLABs have one write port and asynchronous reads, so each copy costs about
// 20 ALMs where the register array cost a flip-flop per bit plus an 8:1 read
// mux per bit and port.
reg valid_q    [7:0][3:0];
reg writable_q [7:0][3:0];
reg user_q     [7:0][3:0];
reg dirty_q    [7:0][3:0];
reg vga_mem    [7:0][3:0];
reg pcd_q      [7:0][3:0];
reg pwt_q      [7:0][3:0];     // PTE.PWT, kept for the TR7 test readback only

reg [2:0] plru [7:0];

localparam bit TRACE_PAGING_EN = 1'b0;

// Registered lookup address decomposition
wire [19:0] lookup_vpn = linear_addr[31:12];
wire [2:0]  lookup_set = lookup_vpn[2:0];       // Set index: VPN[2:0]
wire [16:0] lookup_tag = lookup_vpn[19:3];       // Tag: VPN[19:3]

`Z486_KEEP wire [31:0] lal_w0 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w1 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w2 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w3 = linear_addr_live;

wire [2:0] live_set0 = lal_w0[14:12];  wire [16:0] live_tag0 = lal_w0[31:15];
wire [2:0] live_set1 = lal_w1[14:12];  wire [16:0] live_tag1 = lal_w1[31:15];
wire [2:0] live_set2 = lal_w2[14:12];  wire [16:0] live_tag2 = lal_w2[31:15];
wire [2:0] live_set3 = lal_w3[14:12];  wire [16:0] live_tag3 = lal_w3[31:15];

// Walker refills always target the registered lookup address
// (paging_unit drives update_vpn from tlb_lookup_addr), so the lookup port's
// hit vector doubles as the refill's existing-entry match.
wire [2:0]  update_set = update_vpn[2:0];
wire [16:0] update_tag = update_vpn[19:3];
wire [2:0]  invalidate_set = invalidate_vpn[2:0];
wire [16:0] invalidate_tag = invalidate_vpn[19:3];
// A TR6 request waits for a cycle without a walker update or invalidation.
reg         tlbt_pend_r;
reg  [31:0] tlbt_tr6_r, tlbt_tr7_r;
wire        tlbt_go = tlbt_pend_r && !update_valid && !invalidate_all && !invalidate_page;
wire        tlbt_write = tlbt_go && !tlbt_tr6_r[0];
wire        tlbt_lookup = tlbt_go && tlbt_tr6_r[0];
wire [2:0]  tlbt_set = tlbt_tr6_r[14:12];
wire [16:0] tlbt_tag = tlbt_tr6_r[31:15];
wire [2:0]  tlbt_plru = plru[tlbt_set];
wire [1:0]  tlbt_way = tlbt_tr7_r[4] ? tlbt_tr7_r[3:2] :
                       tlbt_plru[0] ? (tlbt_plru[2] ? 2'd3 : 2'd2) :
                                      (tlbt_plru[1] ? 2'd1 : 2'd0);
wire        tlb_write = reset_n && !invalidate_all && !invalidate_page &&
                        (update_valid || tlbt_write);
wire [1:0]  victim_way;
wire [1:0]  write_way = tlbt_write ? tlbt_way : victim_way;
wire [2:0]  write_set = tlbt_write ? tlbt_set : update_set;
wire [16:0] write_tag = tlbt_write ? tlbt_tag : update_tag;
wire [19:0] write_pfn = tlbt_write ? tlbt_tr7_r[31:12] : update_pfn;

logic [16:0] lookup_tag_q [4];
logic [19:0] lookup_pfn_q [4];
logic [16:0] live_tag_q   [4];
logic [19:0] live_pfn_q   [4];
logic [16:0] inval_tag_q  [4];

// Quartus 17 does not apply ramstyle to memories declared inside a generate
// block (they stay as registers), so the twelve copies are written out flat.
`Z486_DISTRIBUTED_RAM reg [36:0] lookup_copy0 [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] live_copy0   [0:7];
`Z486_DISTRIBUTED_RAM reg [16:0] inval_copy0  [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] lookup_copy1 [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] live_copy1   [0:7];
`Z486_DISTRIBUTED_RAM reg [16:0] inval_copy1  [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] lookup_copy2 [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] live_copy2   [0:7];
`Z486_DISTRIBUTED_RAM reg [16:0] inval_copy2  [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] lookup_copy3 [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] live_copy3   [0:7];
`Z486_DISTRIBUTED_RAM reg [16:0] inval_copy3  [0:7];
// TR6/TR7 lookup read port.
`Z486_DISTRIBUTED_RAM reg [36:0] test_copy0   [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] test_copy1   [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] test_copy2   [0:7];
`Z486_DISTRIBUTED_RAM reg [36:0] test_copy3   [0:7];
always_ff @(posedge clk) begin
    if (tlb_write && write_way == 2'd0) begin
        lookup_copy0[write_set] <= {write_tag, write_pfn};
        live_copy0[write_set]   <= {write_tag, write_pfn};
        inval_copy0[write_set]  <= write_tag;
        test_copy0[write_set]   <= {write_tag, write_pfn};
    end
    if (tlb_write && write_way == 2'd1) begin
        lookup_copy1[write_set] <= {write_tag, write_pfn};
        live_copy1[write_set]   <= {write_tag, write_pfn};
        inval_copy1[write_set]  <= write_tag;
        test_copy1[write_set]   <= {write_tag, write_pfn};
    end
    if (tlb_write && write_way == 2'd2) begin
        lookup_copy2[write_set] <= {write_tag, write_pfn};
        live_copy2[write_set]   <= {write_tag, write_pfn};
        inval_copy2[write_set]  <= write_tag;
        test_copy2[write_set]   <= {write_tag, write_pfn};
    end
    if (tlb_write && write_way == 2'd3) begin
        lookup_copy3[write_set] <= {write_tag, write_pfn};
        live_copy3[write_set]   <= {write_tag, write_pfn};
        inval_copy3[write_set]  <= write_tag;
        test_copy3[write_set]   <= {write_tag, write_pfn};
    end
end
logic [36:0] test_q [4];
// The test read port also serves the sidecar's replacement refresh (below)
// whenever no TR6 request is pending; a pending request owns it.
wire [2:0] vref_set;
wire [2:0] test_rd_set = tlbt_pend_r ? tlbt_set : vref_set;
assign test_q[0] = test_copy0[test_rd_set];
assign test_q[1] = test_copy1[test_rd_set];
assign test_q[2] = test_copy2[test_rd_set];
assign test_q[3] = test_copy3[test_rd_set];
assign {lookup_tag_q[0], lookup_pfn_q[0]} = lookup_copy0[lookup_set];
assign {live_tag_q[0], live_pfn_q[0]}     = live_copy0[live_set0];
assign inval_tag_q[0]                      = inval_copy0[invalidate_set];
assign {lookup_tag_q[1], lookup_pfn_q[1]} = lookup_copy1[lookup_set];
assign {live_tag_q[1], live_pfn_q[1]}     = live_copy1[live_set1];
assign inval_tag_q[1]                      = inval_copy1[invalidate_set];
assign {lookup_tag_q[2], lookup_pfn_q[2]} = lookup_copy2[lookup_set];
assign {live_tag_q[2], live_pfn_q[2]}     = live_copy2[live_set2];
assign inval_tag_q[2]                      = inval_copy2[invalidate_set];
assign {lookup_tag_q[3], lookup_pfn_q[3]} = lookup_copy3[lookup_set];
assign {live_tag_q[3], live_pfn_q[3]}     = live_copy3[live_set3];
assign inval_tag_q[3]                      = inval_copy3[invalidate_set];

// Hit detection - combinational, parallel comparison within selected set
wire hit0 = valid_q[lookup_set][0] && (lookup_tag_q[0] == lookup_tag);
wire hit1 = valid_q[lookup_set][1] && (lookup_tag_q[1] == lookup_tag);
wire hit2 = valid_q[lookup_set][2] && (lookup_tag_q[2] == lookup_tag);
wire hit3 = valid_q[lookup_set][3] && (lookup_tag_q[3] == lookup_tag);

// Compute device classification per way, in parallel with hit detection. This
// avoids putting the selected-PFN mux on cache request routing controls.
assign is_vga_mem = (hit0 && vga_mem[lookup_set][0]) ||
                    (hit1 && vga_mem[lookup_set][1]) ||
                    (hit2 && vga_mem[lookup_set][2]) ||
                    (hit3 && vga_mem[lookup_set][3]);

assign is_pcd = (hit0 && pcd_q[lookup_set][0]) ||
                (hit1 && pcd_q[lookup_set][1]) ||
                (hit2 && pcd_q[lookup_set][2]) ||
                (hit3 && pcd_q[lookup_set][3]);

// Encode hit into 2-bit way index
wire [1:0] hit_way = hit0 ? 2'd0 :
                     hit1 ? 2'd1 :
                     hit2 ? 2'd2 :
                     hit3 ? 2'd3 : 2'd0;

wire live_hit0 = valid_q[live_set0][0] && (live_tag_q[0] == live_tag0);
wire live_hit1 = valid_q[live_set1][1] && (live_tag_q[1] == live_tag1);
wire live_hit2 = valid_q[live_set2][2] && (live_tag_q[2] == live_tag2);
wire live_hit3 = valid_q[live_set3][3] && (live_tag_q[3] == live_tag3);

assign live_is_vga_mem =
    (live_hit0 && vga_mem[live_set0][0]) ||
    (live_hit1 && vga_mem[live_set1][1]) ||
    (live_hit2 && vga_mem[live_set2][2]) ||
    (live_hit3 && vga_mem[live_set3][3]);

// The D2 port uses one synchronous RAM read followed by an EX tag compare.
// It is maintained as an independent TLB: retaining a translation after the
// four-way TLB replaces it is valid until software executes INVLPG or reloads
// CR3, just as retaining it in any other TLB entry would be.
// 256 entries, direct-mapped on VPN[19:12]: one M10K, and no way select on
// the hit path (it feeds D2 issue through a direct load's hit). Fewer
// entries let a program's read and write pages collide (Quake: 32 entries
// cost 1.9%).
localparam integer VIPT_TLB_INDEX_BITS = 8;
localparam integer VIPT_TLB_ENTRIES = 1 << VIPT_TLB_INDEX_BITS;
wire [VIPT_TLB_INDEX_BITS-1:0] vipt_preread_index =
    vipt_linear_addr[19:12];
wire [VIPT_TLB_INDEX_BITS-1:0] vipt_refill_index =
    vipt_refill_linear[19:12];
wire vipt_refill_write = vipt_refill_valid && !update_valid;
reg [31:0] vipt_linear_r;
reg        vipt_hazard_r;
reg        vipt_fresh_r;
reg [VIPT_TLB_ENTRIES-1:0] vipt_valid;
// {VPN tag[19:8], PFN[19:0], writable, user, dirty, VGA}.  A PCD page sets
// the VGA bit too: every direct-path consumer then rejects the page, and its
// accesses take the demand path, which carries the page's PCD.
`Z486_BLOCK_RAM_NO_RW_CHECK reg [35:0] vipt_tlb [0:VIPT_TLB_ENTRIES-1];
reg [35:0] vipt_tlb_q;

always_ff @(posedge clk) begin
    vipt_fresh_r <= vipt_preread;
    if (vipt_preread) begin
        vipt_linear_r <= vipt_linear_addr;
        // Any simultaneous mutation conservatively poisons this preread. TLB
        // mutations are rare, and a false collision only takes the normal
        // authoritative lookup; avoiding the live index compares keeps D2 EA
        // formation out of this register input.
        vipt_hazard_r <= invalidate_all || invalidate_page || update_valid ||
                         vipt_refill_write || tlbt_write;
        vipt_tlb_q <= vipt_tlb[vipt_preread_index];
    end
end

wire vipt_match = vipt_valid[vipt_linear_r[19:12]] && !vipt_hazard_r &&
                  (vipt_tlb_q[35:24] == vipt_linear_r[31:20]);
assign vipt_is_vga_mem = vipt_match && vipt_tlb_q[0];

// THE SIDECAR'S HITS REFRESH THE FOUR-WAY TLB'S REPLACEMENT STATE. A 486
// refreshes a page's pseudo-LRU state on every access that uses it. A sidecar
// hit used to bypass the main TLB entirely, so a page served only from the
// sidecar aged to least-recently-used in its set and was evicted while still
// in use; the next access that needed the main TLB (a locked RMW, a write, or
// any access the direct port declined) walked again. That walk is not
// architecturally free: it rereads the page tables, so software that has
// rewritten them without INVLPG - legal while the translation is cached -
// sees the new mapping, and a walk taken with A20 masked reads them from the
// wrong place (the PC-9821 VEM486 + HSB #PF at 0xFD880, which the real 486
// never takes; tests/programs/tlb_sidecar_lru). One refresh per preread: the
// cycle after it, when vipt_linear_r is the preread's address.
assign vref_set = vipt_linear_r[14:12];
wire [16:0] vref_tag = vipt_linear_r[31:15];
wire [3:0] vref_match = {valid_q[vref_set][3] && (test_q[3][36:20] == vref_tag),
                         valid_q[vref_set][2] && (test_q[2][36:20] == vref_tag),
                         valid_q[vref_set][1] && (test_q[1][36:20] == vref_tag),
                         valid_q[vref_set][0] && (test_q[0][36:20] == vref_tag)};
wire       vref_refresh = vipt_fresh_r && vipt_match && !tlbt_pend_r && (|vref_match);
wire [1:0] vref_way = vref_match[0] ? 2'd0 : vref_match[1] ? 2'd1 :
                      vref_match[2] ? 2'd2 : 2'd3;

always_comb begin
    vipt_hit = vipt_match;
    vipt_physical_addr = {vipt_tlb_q[23:4], vipt_linear_r[11:0]};
    vipt_writable = vipt_tlb_q[3];
    vipt_user = vipt_tlb_q[2];
    vipt_dirty = vipt_tlb_q[1];
    if (!vipt_match) begin
        vipt_physical_addr = vipt_linear_r;
        vipt_writable = 1'b0;
        vipt_user = 1'b0;
        vipt_dirty = 1'b0;
    end
end

always_ff @(posedge clk) begin
    if (update_valid)
        vipt_tlb[update_vpn[7:0]] <= {update_vpn[19:8], update_pfn,
                                      update_writable, update_user,
                                      update_dirty,
                                      update_pcd ||
                                      z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP)};
    else if (vipt_refill_write)
        vipt_tlb[vipt_refill_index] <= {vipt_refill_linear[31:20],
                                        vipt_refill_pfn,
                                        vipt_refill_writable,
                                        vipt_refill_user,
                                        vipt_refill_dirty,
                                        vipt_refill_pcd ||
                                        z486_page_in_window(vipt_refill_pfn, VGA_BASE, VGA_TOP)};
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        vipt_valid <= '0;
    else if (invalidate_all || tlbt_write)
        // A TR6 write rewrites a translation the sidecar may hold; TR6 writes
        // are rare, so drop the whole sidecar rather than decode its index.
        vipt_valid <= '0;
    else if (invalidate_page)
        vipt_valid[invalidate_vpn[7:0]] <= 1'b0;
    else if (update_valid)
        vipt_valid[update_vpn[7:0]] <= 1'b1;
    else if (vipt_refill_write)
        vipt_valid[vipt_refill_index] <= 1'b1;
end

// Output signals - combinational
always_comb begin
    hit = hit0 | hit1 | hit2 | hit3;

    // Select physical address from matching entry
    physical_addr = {lookup_pfn_q[hit_way], linear_addr[11:0]};
    writable = writable_q[lookup_set][hit_way];
    user = user_q[lookup_set][hit_way];
    dirty = dirty_q[lookup_set][hit_way];

    // If no hit, output linear address (will be overridden by page walker result)
    if (!hit) begin
        physical_addr = linear_addr;
        writable = 1'b1;
        user = 1'b0;
        dirty = 1'b0;
    end
end

always_comb begin
    live_hit = live_hit0 | live_hit1 | live_hit2 | live_hit3;
    // Matching translations are unique.  Select each field directly from the
    // one-hot hit vector instead of priority-encoding a way and then muxing;
    // this shortens the live address -> paging/cache finalize cone.
    live_physical_addr = {
        ({20{live_hit0}} & live_pfn_q[0]) |
        ({20{live_hit1}} & live_pfn_q[1]) |
        ({20{live_hit2}} & live_pfn_q[2]) |
        ({20{live_hit3}} & live_pfn_q[3]),
        linear_addr_live[11:0]
    };
    live_writable = !live_hit |
                    (live_hit0 & writable_q[live_set0][0]) |
                    (live_hit1 & writable_q[live_set1][1]) |
                    (live_hit2 & writable_q[live_set2][2]) |
                    (live_hit3 & writable_q[live_set3][3]);
    live_user = (live_hit0 & user_q[live_set0][0]) |
                (live_hit1 & user_q[live_set1][1]) |
                (live_hit2 & user_q[live_set2][2]) |
                (live_hit3 & user_q[live_set3][3]);
    live_dirty = (live_hit0 & dirty_q[live_set0][0]) |
                 (live_hit1 & dirty_q[live_set1][1]) |
                 (live_hit2 & dirty_q[live_set2][2]) |
                 (live_hit3 & dirty_q[live_set3][3]);
end

// PLRU victim selection for the update set (existing entry wins). The
// existing-entry match is the lookup port's hit vector (see update_set above).
assign victim_way = hit0 ? 2'd0 :
                    hit1 ? 2'd1 :
                    hit2 ? 2'd2 :
                    hit3 ? 2'd3 :
                    plru[update_set][0] ? (plru[update_set][2] ? 2'd3 : 2'd2) :
                                          (plru[update_set][1] ? 2'd1 : 2'd0);

// synthesis translate_off
always @(posedge clk)
    if (reset_n && update_valid && update_vpn != lookup_vpn)
        $fatal(1, "TLB refill vpn %05x differs from the registered lookup %05x",
               update_vpn, lookup_vpn);
// synthesis translate_on

wire inval_match0 = valid_q[invalidate_set][0] && inval_tag_q[0] == invalidate_tag;
wire inval_match1 = valid_q[invalidate_set][1] && inval_tag_q[1] == invalidate_tag;
wire inval_match2 = valid_q[invalidate_set][2] && inval_tag_q[2] == invalidate_tag;
wire inval_match3 = valid_q[invalidate_set][3] && inval_tag_q[3] == invalidate_tag;

// TLB state update and PLRU management. Tag/PFN writes are in the MLAB
// copies above, enabled by tlb_write and victim_way.
integer s;
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Invalidate all entries on reset
        for (s = 0; s < 8; s = s + 1) begin
            valid_q[s][0] <= 1'b0;
            valid_q[s][1] <= 1'b0;
            valid_q[s][2] <= 1'b0;
            valid_q[s][3] <= 1'b0;
            plru[s] <= 3'b000;
        end
    end else if (invalidate_all) begin
        // CR3 write - flush entire TLB
        for (s = 0; s < 8; s = s + 1) begin
            valid_q[s][0] <= 1'b0;
            valid_q[s][1] <= 1'b0;
            valid_q[s][2] <= 1'b0;
            valid_q[s][3] <= 1'b0;
            plru[s] <= 3'b000;
        end
    end else if (invalidate_page) begin
        // Multiple matching ways are not expected, but clear every match so
        // INVLPG also repairs any duplicate left by an earlier implementation.
        if (inval_match0) valid_q[invalidate_set][0] <= 1'b0;
        if (inval_match1) valid_q[invalidate_set][1] <= 1'b0;
        if (inval_match2) valid_q[invalidate_set][2] <= 1'b0;
        if (inval_match3) valid_q[invalidate_set][3] <= 1'b0;
    end else begin
        // The sidecar's refresh. It always lands: when the lookup port hits
        // the same set this cycle, the hit's touch below is applied on top of
        // it (later nonblocking assignments win), so the hit way is the most
        // recent and the sidecar's way keeps the half-tree bit that points
        // away from it. Yielding to a same-set hit instead lost every refresh
        // while a loop's code page in that set kept the lookup port hitting.
        if (vref_refresh) begin
            case (vref_way)
                2'd0: begin plru[vref_set][0] <= 1'b1; plru[vref_set][1] <= 1'b1; end
                2'd1: begin plru[vref_set][0] <= 1'b1; plru[vref_set][1] <= 1'b0; end
                2'd2: begin plru[vref_set][0] <= 1'b0; plru[vref_set][2] <= 1'b1; end
                2'd3: begin plru[vref_set][0] <= 1'b0; plru[vref_set][2] <= 1'b0; end
            endcase
        end
        // Update PLRU on hit (point away from accessed way in the hit set)
        if (hit) begin
            case (hit_way)
                2'd0: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b1; end
                2'd1: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b0; end
                2'd2: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b1; end
                2'd3: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b0; end
            endcase
        end

        // Insert new entry from page walker, or from a TR6 write (V/D/U/W
        // from TR6, PFN/PCD/PWT from TR7; the walker's write has priority,
        // so both share one write index).
        if (update_valid || tlbt_write) begin
            valid_q[write_set][write_way]    <= tlbt_write ? tlbt_tr6_r[11] : 1'b1;
            writable_q[write_set][write_way] <= tlbt_write ? tlbt_tr6_r[6] : update_writable;
            user_q[write_set][write_way]     <= tlbt_write ? tlbt_tr6_r[8] : update_user;
            dirty_q[write_set][write_way]    <= tlbt_write ? tlbt_tr6_r[10] : update_dirty;
            vga_mem[write_set][write_way]    <= z486_page_in_window(write_pfn, VGA_BASE, VGA_TOP);
            pcd_q[write_set][write_way]      <= tlbt_write ? tlbt_tr7_r[11] : update_pcd;
            pwt_q[write_set][write_way]      <= tlbt_write ? tlbt_tr7_r[10] : update_pwt;
            case (write_way)
                2'd0: begin plru[write_set][0] <= 1'b1; plru[write_set][1] <= 1'b1; end
                2'd1: begin plru[write_set][0] <= 1'b1; plru[write_set][1] <= 1'b0; end
                2'd2: begin plru[write_set][0] <= 1'b0; plru[write_set][2] <= 1'b1; end
                2'd3: begin plru[write_set][0] <= 1'b0; plru[write_set][2] <= 1'b0; end
            endcase

            // synthesis translate_off
            if (TRACE_PAGING_EN)
                $display("TLB UPDATE: vpn=%05x pfn=%05x writable=%b user=%b set=%0d victim_way=%0d",
                         update_vpn, update_pfn, update_writable, update_user, update_set, victim_way);
            // synthesis translate_on
        end
    end
end

// TR6/TR7 request and lookup result.  A pair of TR6 attribute bits matches a
// clear entry bit (01), a set one (10), either (11) or neither (00).
function automatic logic tlbt_attr_ok(input logic bit_v, input logic want_set,
                                      input logic want_clear);
    tlbt_attr_ok = bit_v ? want_set : want_clear;
endfunction
logic [3:0] tlbt_match;
always_comb begin
    for (int w = 0; w < 4; w++)
        tlbt_match[w] = (valid_q[tlbt_set][w] == tlbt_tr6_r[11]) &&
                        (test_q[w][36:20] == tlbt_tag) &&
                        tlbt_attr_ok(dirty_q[tlbt_set][w], tlbt_tr6_r[10], tlbt_tr6_r[9]) &&
                        tlbt_attr_ok(user_q[tlbt_set][w], tlbt_tr6_r[8], tlbt_tr6_r[7]) &&
                        tlbt_attr_ok(writable_q[tlbt_set][w], tlbt_tr6_r[6], tlbt_tr6_r[5]);
end
wire       tlbt_one = (tlbt_match == 4'b0001) || (tlbt_match == 4'b0010) ||
                      (tlbt_match == 4'b0100) || (tlbt_match == 4'b1000);
wire [1:0] tlbt_hit_way = tlbt_match[0] ? 2'd0 : tlbt_match[1] ? 2'd1 :
                          tlbt_match[2] ? 2'd2 : 2'd3;
always_ff @(posedge clk) begin
    if (!reset_n) begin
        tlbt_pend_r <= 1'b0;
        tlbt_done <= 1'b0;
        tlbt_lookup_done <= 1'b0;
        tlbt_tr6_r <= 32'd0;
        tlbt_tr7_r <= 32'd0;
        tlbt_tr6_out <= 32'd0;
        tlbt_tr7_out <= 32'd0;
    end else begin
        tlbt_done <= tlbt_go;
        tlbt_lookup_done <= tlbt_lookup;
        if (tlbt_req) begin
            tlbt_pend_r <= 1'b1;
            tlbt_tr6_r <= tlbt_tr6;
            tlbt_tr7_r <= tlbt_tr7;
        end else if (tlbt_go) begin
            tlbt_pend_r <= 1'b0;
        end
        if (tlbt_lookup) begin
            // LRU reports the state before the lookup; PL reports a single hit.
            tlbt_tr7_out <= {tlbt_one ? test_q[tlbt_hit_way][19:0] : tlbt_tr7_r[31:12],
                             tlbt_one ? pcd_q[tlbt_set][tlbt_hit_way] : 1'b0,
                             tlbt_one ? pwt_q[tlbt_set][tlbt_hit_way] : 1'b0,
                             tlbt_plru, 2'b00, tlbt_one,
                             tlbt_one ? tlbt_hit_way : 2'b00, 2'b00};
            tlbt_tr6_out <= tlbt_one
                ? {tlbt_tr6_r[31:12], valid_q[tlbt_set][tlbt_hit_way],
                   dirty_q[tlbt_set][tlbt_hit_way], !dirty_q[tlbt_set][tlbt_hit_way],
                   user_q[tlbt_set][tlbt_hit_way], !user_q[tlbt_set][tlbt_hit_way],
                   writable_q[tlbt_set][tlbt_hit_way], !writable_q[tlbt_set][tlbt_hit_way],
                   4'b0000, tlbt_tr6_r[0]}
                : tlbt_tr6_r;
        end
    end
end

endmodule
