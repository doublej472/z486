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

    // Update interface (from page walker)
    input               update_valid,
    input        [19:0] update_vpn,     // Virtual page number
    input        [19:0] update_pfn,     // Physical frame number
    input               update_writable,
    input               update_user,
    input               update_dirty,

    // Invalidate all entries (on CR3 write)
    input               invalidate_all,

    // Invalidate every cached translation for one linear page (INVLPG).
    input               invalidate_page,
    input        [19:0] invalidate_vpn
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
wire        tlb_write = reset_n && !invalidate_all && !invalidate_page && update_valid;
wire [1:0]  victim_way;

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
always_ff @(posedge clk) begin
    if (tlb_write && victim_way == 2'd0) begin
        lookup_copy0[update_set] <= {update_tag, update_pfn};
        live_copy0[update_set]   <= {update_tag, update_pfn};
        inval_copy0[update_set]  <= update_tag;
    end
    if (tlb_write && victim_way == 2'd1) begin
        lookup_copy1[update_set] <= {update_tag, update_pfn};
        live_copy1[update_set]   <= {update_tag, update_pfn};
        inval_copy1[update_set]  <= update_tag;
    end
    if (tlb_write && victim_way == 2'd2) begin
        lookup_copy2[update_set] <= {update_tag, update_pfn};
        live_copy2[update_set]   <= {update_tag, update_pfn};
        inval_copy2[update_set]  <= update_tag;
    end
    if (tlb_write && victim_way == 2'd3) begin
        lookup_copy3[update_set] <= {update_tag, update_pfn};
        live_copy3[update_set]   <= {update_tag, update_pfn};
        inval_copy3[update_set]  <= update_tag;
    end
end
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
reg [VIPT_TLB_ENTRIES-1:0] vipt_valid;
// {VPN tag[19:8], PFN[19:0], writable, user, dirty, VGA}
`Z486_BLOCK_RAM_NO_RW_CHECK reg [35:0] vipt_tlb [0:VIPT_TLB_ENTRIES-1];
reg [35:0] vipt_tlb_q;

always_ff @(posedge clk) begin
    if (vipt_preread) begin
        vipt_linear_r <= vipt_linear_addr;
        // Any simultaneous mutation conservatively poisons this preread. TLB
        // mutations are rare, and a false collision only takes the normal
        // authoritative lookup; avoiding the live index compares keeps D2 EA
        // formation out of this register input.
        vipt_hazard_r <= invalidate_all || invalidate_page || update_valid ||
                         vipt_refill_write;
        vipt_tlb_q <= vipt_tlb[vipt_preread_index];
    end
end

wire vipt_match = vipt_valid[vipt_linear_r[19:12]] && !vipt_hazard_r &&
                  (vipt_tlb_q[35:24] == vipt_linear_r[31:20]);
assign vipt_is_vga_mem = vipt_match && vipt_tlb_q[0];

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
                                      z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP)};
    else if (vipt_refill_write)
        vipt_tlb[vipt_refill_index] <= {vipt_refill_linear[31:20],
                                        vipt_refill_pfn,
                                        vipt_refill_writable,
                                        vipt_refill_user,
                                        vipt_refill_dirty,
                                        z486_page_in_window(vipt_refill_pfn, VGA_BASE, VGA_TOP)};
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        vipt_valid <= '0;
    else if (invalidate_all)
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
        // Update PLRU on hit (point away from accessed way in the hit set)
        if (hit) begin
            case (hit_way)
                2'd0: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b1; end
                2'd1: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b0; end
                2'd2: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b1; end
                2'd3: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b0; end
            endcase
        end

        // Insert new entry from page walker
        if (update_valid) begin
            valid_q[update_set][victim_way]    <= 1'b1;
            writable_q[update_set][victim_way] <= update_writable;
            user_q[update_set][victim_way]     <= update_user;
            dirty_q[update_set][victim_way]    <= update_dirty;
            vga_mem[update_set][victim_way]    <= z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP);
            case (victim_way)
                2'd0: begin plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b1; end
                2'd1: begin plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b0; end
                2'd2: begin plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b1; end
                2'd3: begin plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b0; end
            endcase

            // synthesis translate_off
            if (TRACE_PAGING_EN)
                $display("TLB UPDATE: vpn=%05x pfn=%05x writable=%b user=%b set=%0d victim_way=%0d",
                         update_vpn, update_pfn, update_writable, update_user, update_set, victim_way);
            // synthesis translate_on
        end
    end
end

endmodule
