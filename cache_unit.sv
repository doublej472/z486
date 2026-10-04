//
// Cache Unit
// A20 masking, the instruction and data caches, the VIPT load port and request steering
//
`include "z486_platform.svh"
module cache_unit
    import z486_pkg::*, z486_cache_map_pkg::*;
#(
    parameter PROTECT_UMA_ROM = 0,
    parameter DCACHE_SET_BITS = 7,
    parameter ICACHE_SET_BITS = 7,
    parameter ENABLE_DEVICE_MMIO = 0,
    parameter [31:0] DEVICE_MMIO_MASK = 32'hff00_0000,

    // A20 gate masks, applied closed / open. Default = PC/AT bit-20 clear /
    // unmasked. The PC-98 preset overrides A20_MASK_OFF (wrap into 1 MiB).
    parameter [31:0] A20_MASK_OFF = 32'hffef_ffff,
    parameter [31:0] A20_MASK_ON  = 32'hffff_ffff,

    // VGA/device A0000-BFFFF template window (VGA_ENABLE gates only this copy).
    // VGA_PRE_WRAP: 1 = raw, 0 = A20-masked.
    parameter        VGA_ENABLE = 0,
    parameter        VGA_PRE_WRAP = 1,
    parameter [1:0]  VGA_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] VGA_BASE = 32'h000a_0000,
    parameter [31:0] VGA_TOP  = 32'h000b_ffff,

    // Device aperture (PC-98: A0000-FFFFF). Disabled by default.
    parameter        APERTURE_ENABLE = 0,
    parameter [1:0]  APERTURE_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] APERTURE_BASE = 32'h000a_0000,
    parameter [31:0] APERTURE_TOP  = 32'h000f_ffff,

    // Device-memory aliases (PC-98 mirror/PEGC/fw_high). Disabled by default.
    parameter        ALIAS_ENABLE = 0,
    parameter [1:0]  ALIAS_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] ALIAS0_BASE = 32'h00f0_0000,
    parameter [31:0] ALIAS0_TOP  = 32'h00ff_ffff,
    parameter [31:0] ALIAS1_BASE = 32'hfff0_0000,
    parameter [31:0] ALIAS1_TOP  = 32'hfff7_ffff,
    parameter [31:0] ALIAS2_BASE = 32'hffff_8000,
    parameter [31:0] ALIAS2_TOP  = 32'hffff_ffff,

    // Window-0 overlay range (PC-98 0x80000-0x9FFFF), enabled only when win0_unmapped.
    parameter        WIN0_ENABLE = 0,
    parameter [1:0]  WIN0_CLASS = Z486_CACHE_NO_ALLOC,
    parameter [31:0] WIN0_BASE = 32'h0008_0000,
    parameter [31:0] WIN0_TOP  = 32'h0009_ffff,

    // No-allocate bound: addresses at or above it never install a line.
    parameter        NO_ALLOC_ENABLE = 0,
    parameter [1:0]  NO_ALLOC_CLASS = Z486_CACHE_NO_ALLOC,
    parameter [31:0] NO_ALLOC_BOUND = 32'h0800_0000,

    // Runtime cacheable-RAM top; with RAM_BOUND_ENABLE the effective bound is
    // min(ram_cache_top, NO_ALLOC_BOUND).
    parameter        RAM_BOUND_ENABLE = 0
)
(
    // Clock, reset and board configuration
    input  logic clk,
    input  logic reset_n,
    input  logic a20_enable,
    input  logic device_mmio_enable,
    input  logic [31:0] device_mmio_base,
    // Window-0 overlay verdict (0x80000-0x9FFFF target is not RAM); the
    // template's WIN0 window is enabled only while this is asserted.
    input  logic win0_unmapped,
    // The platform's cacheable-RAM top; only read when RAM_BOUND_ENABLE is set.
    input  logic [31:0] ram_cache_top,

    // Paging unit: demand data request (physical address, before A20 masking)
    input  logic dcache_req_valid,
    input  logic [31:0] dcache_req_phys_addr_raw,
    input  logic [11:0] dcache_req_preread_offset,
    input  logic dcache_req_preread_priority,
    input  logic dcache_req_write,
    input  logic [3:0] dcache_req_be,
    input  logic [31:0] dcache_req_wdata,
    input  logic dcache_req_is_io,
    input  logic dcache_req_is_inta,
    input  logic dcache_req_is_vga_mem,

    // Execution core: WR_FAST store and VIPT load/RMW preread
    input  logic fast_store_valid,
    input  logic [31:0] fast_store_phys_addr_raw,
    input  logic [3:0] fast_store_be,
    input  logic [31:0] fast_store_wdata,
    output logic fast_store_accepted,
    input  logic dcache_vipt_probe_valid,
    input  logic [11:0] dcache_vipt_probe_offset,
    output logic dcache_vipt_probe_ready,
    output logic dcache_vipt_probe_accepted,
    output logic dcache_vipt_probe_direct_accepted,
    input  logic dcache_vipt_resolve_valid,
    input  logic [31:0] dcache_vipt_resolve_phys_addr_raw,
    output logic dcache_vipt_resolve_hit,
    output logic [31:0] dcache_vipt_resolve_data,

    // Paging unit: instruction line request (prefetch)
    input  logic icache_req_valid,
    input  logic [31:0] icache_req_phys_addr_raw,
    output logic icache_req_accepted,
    output logic icache_req_complete,
    output logic [127:0] icache_rdata,

    // Bus interface unit: request routing and D-cache CPU response
    input  logic x87_req_selected,
    output logic normal_cache_req,
    output logic dcache_req_is_device_mmio,
    output logic dcache_req_is_uncached,
    output logic dcache_req_is_direct,
    output logic [31:0] dcache_req_phys_addr,
    output logic dcache_cpu_ready,
    output logic dcache_cpu_wr_ready,
    output logic dcache_cpu_resp_valid,
    output logic [31:0] dcache_cpu_dout,
    output logic dcache_stores_drained,

    // Bus interface unit: line fills and write-buffer drain (KBA/KBWR/KBRD)
    output logic dcache_mem_valid,
    output logic [31:0] dcache_mem_addr,
    output logic dcache_mem_write,
    output logic [3:0] dcache_mem_be,
    output logic [7:0] dcache_mem_burstcount,
    output logic [31:0] dcache_mem_din,
    input  logic dcache_mem_ready,
    input  logic dcache_mem_resp_valid,
    input  logic dcache_mem_line_resp_valid,
    output logic icache_mem_valid,
    output logic [31:0] icache_mem_addr,
    output logic [3:0] icache_mem_be,
    output logic [7:0] icache_mem_burstcount,
    input  logic icache_mem_ready,
    input  logic icache_mem_resp_valid,
    input  logic icache_mem_line_resp_valid,
    input  logic ext_valid_r,
    input  logic direct_rd_pending,
    input  logic dcache_read_pending,
    input  logic icache_read_pending,
    input  logic [31:0] din,
    input  logic [127:0] line_din,

    // External coherence (snoop invalidation)
    input  logic [31:0] snoop_addr,
    input  logic snoop_valid,

    // Native whole-L1 invalidate (486 INVD/WBINVD).  Two request sources are
    // arbitrated here, not ORed at the z486 boundary: `cache_flush` is the
    // platform's held level (one walk per release), `cache_flush_insn` is the
    // instruction path's held level (latched, so a request during a walk is
    // queued rather than dropped).  busy is high for the whole walk and done
    // pulses once per completed walk.
    input  logic cache_flush,
    input  logic cache_flush_insn,
    output logic cache_flush_busy,
    output logic cache_flush_done,
    // Merged I-cache invalidation (external snoop + template DIRECT-write
    // invalidation), produced by the bus unit.
    input  logic [31:0] icache_invalidate_addr,
    input  logic icache_invalidate_valid
);


// A20 masking; the default masks reproduce upstream exactly.
wire [31:0] dcache_req_a20_mask = (a20_enable || dcache_req_is_io)
                                ? A20_MASK_ON : A20_MASK_OFF;
assign dcache_req_phys_addr = dcache_req_phys_addr_raw & dcache_req_a20_mask;
wire [31:0] dcache_vipt_resolve_phys_addr = dcache_vipt_resolve_phys_addr_raw &
                                            (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
wire [31:0] fast_store_phys_addr = fast_store_phys_addr_raw &
                                   (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
wire [31:0] icache_req_phys_addr = icache_req_phys_addr_raw &
                                   (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
assign dcache_req_is_device_mmio = ENABLE_DEVICE_MMIO &&
                                  device_mmio_enable &&
                                  ((dcache_req_phys_addr & DEVICE_MMIO_MASK) ==
                                   (device_mmio_base & DEVICE_MMIO_MASK));
wire dcache_vipt_is_device_mmio = ENABLE_DEVICE_MMIO &&
                                   device_mmio_enable &&
                                   ((dcache_vipt_resolve_phys_addr &
                                     DEVICE_MMIO_MASK) ==
                                    (device_mmio_base & DEVICE_MMIO_MASK));

// z486_window_match assumes the A20 mask only clears bits [31:20]; assert it once.
// synthesis translate_off
initial begin
    if (A20_MASK_OFF[19:0] !== 20'hfffff)
        $fatal(1, "z486 A20MASK: A20_MASK_OFF[19:0] must be all ones (%h)", A20_MASK_OFF);
    if (A20_MASK_ON[19:0] !== 20'hfffff)
        $fatal(1, "z486 A20MASK: A20_MASK_ON[19:0] must be all ones (%h)", A20_MASK_ON);
    if (NO_ALLOC_ENABLE &&
        ({1'b0, NO_ALLOC_BOUND} > (33'd1 << `Z486_L1_PHYS_ADDR_BITS)))
        $fatal(1, "z486 NO_ALLOC_BOUND %h exceeds the L1 tag reach %0h (Z486_L1_PHYS_ADDR_BITS=%0d)",
               NO_ALLOC_BOUND, 33'd1 << `Z486_L1_PHYS_ADDR_BITS, `Z486_L1_PHYS_ADDR_BITS);
    // The paging TLB classifies this window per 4 KB page, the unpaged path per
    // byte; a window that does not cover whole pages would disagree.
    if (VGA_BASE[11:0] !== 12'h000)
        $fatal(1, "z486 VGA_BASE %h is not page-aligned (VGA_BASE[11:0] must be 0)", VGA_BASE);
    if (VGA_TOP[11:0] !== 12'hfff)
        $fatal(1, "z486 VGA_TOP %h must end on a page boundary (VGA_TOP[11:0] must be fff)", VGA_TOP);
end
// synthesis translate_on

// Memory-map classification: the paging unit's VGA verdict is a floor; template
// windows only add uncached classes (a constant with none enabled).
localparam bit Z486_TEMPLATE_WINDOWS = VGA_ENABLE | APERTURE_ENABLE |
                                       ALIAS_ENABLE | WIN0_ENABLE |
                                       NO_ALLOC_ENABLE;

// Quartus 17 rejects a user-enum-typed net; carry the class as a plain 2-bit vector.
wire [1:0] dcache_vipt_class;
wire icache_req_is_no_alloc;

// The runtime cacheable-RAM bound: min(ram_cache_top, NO_ALLOC_BOUND) keeps the
// L1-tag-reach check above as the hard ceiling; the runtime input can only tighten it.
wire [31:0] no_alloc_bound_eff = (RAM_BOUND_ENABLE &&
                                  (ram_cache_top < NO_ALLOC_BOUND))
                               ? ram_cache_top : NO_ALLOC_BOUND;

generate
if (Z486_TEMPLATE_WINDOWS) begin : g_memmap_windows
    wire [1:0] dcache_req_class;
    wire [31:0] dcache_vga_addr = VGA_PRE_WRAP ? dcache_req_phys_addr_raw
                                               : dcache_req_phys_addr;
    assign dcache_req_class = z486_classify_phys(
        dcache_req_phys_addr_raw, dcache_req_phys_addr, dcache_vga_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, no_alloc_bound_eff);
    assign dcache_vipt_class = z486_classify_phys(
        dcache_vipt_resolve_phys_addr_raw, dcache_vipt_resolve_phys_addr,
        dcache_vipt_resolve_phys_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, no_alloc_bound_eff);
    assign dcache_req_is_uncached = dcache_req_is_vga_mem ||
                                    (dcache_req_class != Z486_CACHE_CACHEABLE);
    assign dcache_req_is_direct = (dcache_req_class == Z486_CACHE_DIRECT);
    assign icache_req_is_no_alloc = (z486_classify_phys(
        icache_req_phys_addr_raw, icache_req_phys_addr, icache_req_phys_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, no_alloc_bound_eff) == Z486_CACHE_NO_ALLOC);
end else begin : g_memmap_inert
    // Structural no-op: upstream VGA-only demand verdict.
    assign dcache_vipt_class = Z486_CACHE_CACHEABLE;
    assign dcache_req_is_uncached = dcache_req_is_vga_mem;
    assign dcache_req_is_direct = 1'b0;
    assign icache_req_is_no_alloc = 1'b0;
end
endgenerate

// synthesis translate_off
// DEFAULT-EQUIVALENCE FUSES: the default parameter set must reproduce upstream's
// hard-coded PC/AT classification exactly.  These compare the parameterised
// form against a literal copy of the original expression on the live request
// stream, so every regression run re-proves the default equivalence.
always @* begin : memmap_equiv_fuse
    logic [31:0] ref_d, ref_v, ref_f, ref_i;
    logic ref_uncached;
    ref_uncached = 1'b0;
    if (A20_MASK_OFF == ~32'h0010_0000 && A20_MASK_ON == 32'hffff_ffff) begin
        ref_d = (!a20_enable && !dcache_req_is_io)
              ? (dcache_req_phys_addr_raw & ~32'h0010_0000)
              : dcache_req_phys_addr_raw;
        ref_v = !a20_enable
              ? (dcache_vipt_resolve_phys_addr_raw & ~32'h0010_0000)
              : dcache_vipt_resolve_phys_addr_raw;
        ref_f = !a20_enable
              ? (fast_store_phys_addr_raw & ~32'h0010_0000)
              : fast_store_phys_addr_raw;
        ref_i = !a20_enable
              ? (icache_req_phys_addr_raw & ~32'h0010_0000)
              : icache_req_phys_addr_raw;
        if ((dcache_req_phys_addr !== ref_d) ||
            (dcache_vipt_resolve_phys_addr !== ref_v) ||
            (fast_store_phys_addr !== ref_f) || (icache_req_phys_addr !== ref_i))
            $fatal(1, "A20MUX FUSE MISMATCH");
    end
    if (!Z486_TEMPLATE_WINDOWS && VGA_BASE == 32'h000a_0000 &&
        VGA_TOP == 32'h000b_ffff && dcache_req_valid) begin
        ref_uncached = z486_addr_in_window(dcache_req_phys_addr_raw,
                                           32'h000a_0000, 32'h000b_ffff);
        if (ref_uncached !== dcache_req_is_uncached)
            $fatal(1, "MEMMAP UNCACHED FUSE MISMATCH raw=%h got=%b ref=%b",
                   dcache_req_phys_addr_raw, dcache_req_is_uncached, ref_uncached);
    end
    // The demand VGA verdict comes from the paging unit (per page); this checks
    // the platform's window is what that path classifies.
    if (VGA_ENABLE && VGA_PRE_WRAP && VGA_CLASS == Z486_CACHE_DIRECT &&
        dcache_req_valid) begin
        ref_uncached = z486_addr_in_window(dcache_req_phys_addr_raw, VGA_BASE, VGA_TOP);
        if (ref_uncached !== dcache_req_is_vga_mem)
            $fatal(1, "MEMMAP VGA FUSE MISMATCH raw=%h window=%b input=%b",
                   dcache_req_phys_addr_raw, ref_uncached, dcache_req_is_vga_mem);
    end
end
// synthesis translate_on

// dcache_cpu_dout: port
wire        dcache_vipt_resolve_hit_cache;
// dcache_cpu_ready: port
// dcache_cpu_resp_valid: port
// dcache_stores_drained: port
wire [31:0] dcache_store_patch_addr;
wire [31:0] dcache_store_patch_data;
wire  [3:0] dcache_store_patch_be;
wire        dcache_store_patch_valid;
// dcache_mem_addr: port
// dcache_mem_din: port
// dcache_mem_be: port
// dcache_mem_burstcount: port
// dcache_mem_valid: port
// dcache_mem_write: port

wire [127:0] icache_cpu_line;
wire         icache_cpu_ready;
wire         icache_cpu_resp_valid;
// icache_mem_addr: port
// icache_mem_be: port
// icache_mem_burstcount: port
// icache_mem_valid: port

assign dcache_vipt_resolve_hit = dcache_vipt_resolve_hit_cache &&
                                  !dcache_vipt_is_device_mmio &&
                                  (dcache_vipt_class == Z486_CACHE_CACHEABLE);

logic       dcache_cpu_rd_pending;
logic       icache_cpu_rd_pending;

// VGA aperture accesses are device transactions. Bypass the posted L1 store
// queue so an ET4000 bank-register write cannot overtake framebuffer writes.
// The template's uncached windows are routed around the D-cache the same way.
assign normal_cache_req = dcache_req_valid && !dcache_req_is_io &&
                        !dcache_req_is_inta && !dcache_req_is_uncached &&
                        !dcache_req_is_device_mmio &&
                        !x87_req_selected;
wire dcache_cpu_req = fast_store_valid || normal_cache_req;
wire [31:0] dcache_cpu_addr = fast_store_valid ? fast_store_phys_addr
                                              : dcache_req_phys_addr;
wire [31:0] dcache_cpu_wdata = fast_store_valid ? fast_store_wdata
                                               : dcache_req_wdata;
wire [3:0] dcache_cpu_be = fast_store_valid ? fast_store_be : dcache_req_be;
wire dcache_cpu_write = fast_store_valid || dcache_req_write;
// WR_FAST already owns a translated physical address.  Its request must also
// own the synchronous RAM preread; leaving the normal paging preread here
// makes the following S_LOOKUP compare against an unrelated set.
wire [11:0] dcache_cpu_preread_offset = fast_store_valid
                                      ? fast_store_phys_addr[11:0]
                                      : dcache_req_preread_offset;
wire dcache_cpu_preread_priority = fast_store_valid ||
                                   dcache_req_preread_priority;

wire dcache_read_accept = normal_cache_req && !dcache_req_write && dcache_cpu_ready;
wire icache_read_accept = icache_req_valid && icache_cpu_ready;
wire dcache_read_done = dcache_cpu_resp_valid &&
                        (dcache_cpu_rd_pending || dcache_read_accept);
wire icache_read_done = icache_cpu_resp_valid &&
                        (icache_cpu_rd_pending || icache_read_accept);

logic       icache_write_snoop_pending;
logic [31:0] icache_write_snoop_addr_r;
logic [31:0] icache_write_snoop_data_r;
logic  [3:0] icache_write_snoop_be_r;
// Normally the I-cache consumes the D-cache's registered S_LOOKUP store
// directly.  The one-entry pending slot only resolves an external invalidate
// collision (or holds the following store while an older pending patch is
// consumed), preserving invalidate priority without returning to live paging
// request signals.
wire icache_write_patch_valid = !snoop_valid &&
                                (icache_write_snoop_pending ||
                                 dcache_store_patch_valid);
wire [31:0] icache_write_patch_addr = icache_write_snoop_pending
                                    ? icache_write_snoop_addr_r
                                    : dcache_store_patch_addr;
wire [31:0] icache_write_patch_data = icache_write_snoop_pending
                                    ? icache_write_snoop_data_r
                                    : dcache_store_patch_data;
wire [3:0] icache_write_patch_be = icache_write_snoop_pending
                                 ? icache_write_snoop_be_r
                                 : dcache_store_patch_be;

assign fast_store_accepted = fast_store_valid && dcache_cpu_wr_ready;

assign icache_req_accepted = icache_cpu_ready;
assign icache_req_complete = icache_cpu_resp_valid;
assign icache_rdata = icache_cpu_line;

// Cache-side request tracking and the I-cache write-patch slot.
always_ff @(posedge clk) begin
    if (!reset_n) begin
        dcache_cpu_rd_pending <= 1'b0;
        icache_cpu_rd_pending <= 1'b0;
        icache_write_snoop_pending <= 1'b0;
        icache_write_snoop_addr_r <= 32'h0;
        icache_write_snoop_data_r <= 32'h0;
        icache_write_snoop_be_r <= 4'h0;
    end else begin
        if (dcache_store_patch_valid &&
            (snoop_valid || icache_write_snoop_pending)) begin
            // The pending patch, when present, is consumed on this edge. Keep
            // the newly accepted store for the following cycle.
            icache_write_snoop_pending <= 1'b1;
            icache_write_snoop_addr_r <= dcache_store_patch_addr;
            icache_write_snoop_data_r <= dcache_store_patch_data;
            icache_write_snoop_be_r <= dcache_store_patch_be;
        end else if (icache_write_snoop_pending && !snoop_valid) begin
            icache_write_snoop_pending <= 1'b0;
        end

        if (dcache_read_accept && !dcache_read_done)
            dcache_cpu_rd_pending <= 1'b1;
        else if (dcache_read_done)
            dcache_cpu_rd_pending <= 1'b0;

        if (icache_read_accept && !icache_read_done)
            icache_cpu_rd_pending <= 1'b1;
        else if (icache_read_done)
            icache_cpu_rd_pending <= 1'b0;
    end
end

//=============================================================================
// Native whole-L1 flush controller
//=============================================================================
// One walk covers both L1s.  Posted stores are drained first: a store the bus
// has already accepted cannot fall behind the walk, so the drain completes as
// soon as the queue empties, and a walk cannot be overtaken by an older store
// draining during it.  Both caches then walk their sets in parallel: each
// latches the one-cycle request and starts from S_IDLE, so an in-flight fill
// from before the flush completes first and its line is invalidated by the
// walk that follows.
//
// The platform `cache_flush` is armed while its input is low, so a held level is
// one walk.  `cache_flush_insn` has its own arm bit and a pending latch, so a
// request during a walk starts a following one instead of being dropped.
localparam [1:0] CF_IDLE  = 2'd0;
localparam [1:0] CF_DRAIN = 2'd1;
localparam [1:0] CF_WALK  = 2'd2;

wire         dcache_flush_busy;
wire         dcache_flush_done;
wire         icache_flush_busy;
wire         icache_flush_done;

reg  [1:0] cf_state;
reg        cf_armed_r;        // platform request path re-armed (input seen low)
reg        cf_insn_armed_r;   // instruction request path re-armed (input seen low)
reg        cf_insn_pending_r; // instruction request latched, not yet walked
reg        cf_d_done_r;
reg        cf_i_done_r;
reg        cache_flush_done_r;
reg        cf_start_r;       // one-cycle request pulse to both caches

// A held instruction level counts once (re-armed only when released).
wire cf_insn_edge = cache_flush_insn && cf_insn_armed_r;
wire cf_plat_req = cache_flush && cf_armed_r;
wire cf_req = cf_plat_req || cf_insn_edge || cf_insn_pending_r;
wire cache_flush_start = cf_req && (cf_state == CF_IDLE);
wire cf_drain_ready = dcache_stores_drained;
// The cycle the caches actually begin their walk (the merge point for a request
// that arrived during the drain).
wire cf_launch = ((cf_state == CF_IDLE) && cache_flush_start && cf_drain_ready) ||
                 ((cf_state == CF_DRAIN) && cf_drain_ready);

assign cache_flush_busy = (cf_state != CF_IDLE);
assign cache_flush_done = cache_flush_done_r;

always_ff @(posedge clk) begin
    if (!reset_n) begin
        cf_state <= CF_IDLE;
        cf_armed_r <= 1'b1;
        cf_insn_armed_r <= 1'b1;
        cf_insn_pending_r <= 1'b0;
        cf_d_done_r <= 1'b0;
        cf_i_done_r <= 1'b0;
        cf_start_r <= 1'b0;
        cache_flush_done_r <= 1'b0;
    end else begin
        cf_start_r <= cf_launch;
        cache_flush_done_r <= 1'b0;

        // A held platform request re-arms only when released.
        if (!cache_flush)
            cf_armed_r <= 1'b1;

        // The instruction path: release re-arms it; a request seen before the
        // walk starts is latched (a pulse during a walk is not lost); starting
        // the walk consumes both the pending latch and the held level.
        if (!cache_flush_insn)
            cf_insn_armed_r <= 1'b1;
        if (cf_insn_edge && !cf_launch)
            cf_insn_pending_r <= 1'b1;
        if (cf_launch) begin
            cf_insn_pending_r <= 1'b0;
            if (cache_flush_insn)
                cf_insn_armed_r <= 1'b0;
        end

        // Stores that are already accepted by the bus cannot fall behind the
        // walk, so the drain completes as soon as the queue empties.
        if (cf_launch)
            cf_state <= CF_WALK;

        unique case (cf_state)
            CF_IDLE: begin
                if (cache_flush_start) begin
                    cf_d_done_r <= 1'b0;
                    cf_i_done_r <= 1'b0;
                    if (cf_plat_req)
                        cf_armed_r <= 1'b0;
                    if (!cf_drain_ready)
                        cf_state <= CF_DRAIN;
                end
            end
            CF_DRAIN: ;
            CF_WALK: begin
                if (dcache_flush_done)
                    cf_d_done_r <= 1'b1;
                if (icache_flush_done)
                    cf_i_done_r <= 1'b1;
                if ((cf_d_done_r || dcache_flush_done) &&
                    (cf_i_done_r || icache_flush_done)) begin
                    cache_flush_done_r <= 1'b1;
                    cf_state <= CF_IDLE;
                end
            end
            default: cf_state <= CF_IDLE;
        endcase
    end
end

l1_cache #(
    .PROTECT_UMA_ROM(PROTECT_UMA_ROM),
    .SET_BITS(DCACHE_SET_BITS)
) dcache_inst (
    .clk(clk),
    .reset(!reset_n),
    .cpu_addr(dcache_cpu_addr),
    .cpu_preread_offset(dcache_cpu_preread_offset),
    .cpu_preread_priority(dcache_cpu_preread_priority),
    .cpu_din(dcache_cpu_wdata),
    .cpu_dout(dcache_cpu_dout),
    .cpu_be(dcache_cpu_be),
    .cpu_valid(dcache_cpu_req),
    .cpu_write(dcache_cpu_write),
    // I/O, INTA, x87, and VGA/device transactions are routed around this
    // cache above, so accepted D-cache requests need no physical-address
    // aperture decode on their register inputs.
    .cpu_uncacheable(1'b0),
    .cpu_ready(dcache_cpu_ready),
    .cpu_wr_ready(dcache_cpu_wr_ready),
    .store_patch_busy(snoop_valid || icache_write_snoop_pending),
    .flush_req(cf_start_r),
    .flush_busy(dcache_flush_busy),
    .flush_done(dcache_flush_done),
    .cpu_resp_valid(dcache_cpu_resp_valid),
    .stores_drained(dcache_stores_drained),
    .store_patch_addr(dcache_store_patch_addr),
    .store_patch_data(dcache_store_patch_data),
    .store_patch_be(dcache_store_patch_be),
    .store_patch_valid(dcache_store_patch_valid),
    .vipt_probe_offset(dcache_vipt_probe_offset),
    .vipt_probe_valid(dcache_vipt_probe_valid),
    .vipt_probe_ready(dcache_vipt_probe_ready),
    .vipt_probe_accepted(dcache_vipt_probe_accepted),
    .vipt_probe_direct_accepted(dcache_vipt_probe_direct_accepted),
    .vipt_resolve_phys_addr(dcache_vipt_resolve_phys_addr),
    .vipt_resolve_valid(dcache_vipt_resolve_valid),
    .vipt_resolve_data(dcache_vipt_resolve_data),
    .vipt_resolve_hit(dcache_vipt_resolve_hit_cache),
    .mem_addr(dcache_mem_addr),
    .mem_din(dcache_mem_din),
    .mem_dout(din),
    .mem_line_dout(line_din),
    .mem_be(dcache_mem_be),
    .mem_burstcount(dcache_mem_burstcount),
    .mem_busy(ext_valid_r || direct_rd_pending || icache_read_pending),
    .mem_valid(dcache_mem_valid),
    .mem_write(dcache_mem_write),
    .mem_ready(dcache_mem_ready),
    .mem_resp_valid(dcache_mem_resp_valid),
    .mem_line_resp_valid(dcache_mem_line_resp_valid),
    .snoop_addr(snoop_addr),
    .snoop_valid(snoop_valid),
    .cache_enable(1'b1)
);

l1_icache #(
    .SET_BITS(ICACHE_SET_BITS)
) icache_inst (
    .clk(clk),
    .reset(!reset_n),
    .cpu_addr(icache_req_phys_addr),
    .cpu_line(icache_cpu_line),
    .cpu_valid(icache_req_valid),
    .cpu_ready(icache_cpu_ready),
    .cpu_resp_valid(icache_cpu_resp_valid),
    .mem_addr(icache_mem_addr),
    .mem_dout(din),
    .mem_line_dout(line_din),
    .mem_be(icache_mem_be),
    .mem_burstcount(icache_mem_burstcount),
    .mem_busy(ext_valid_r || direct_rd_pending || dcache_read_pending ||
              dcache_mem_valid),
    .mem_valid(icache_mem_valid),
    .mem_ready(icache_mem_ready),
    .mem_resp_valid(icache_mem_resp_valid),
    .mem_line_resp_valid(icache_mem_line_resp_valid),
    .patch_addr(icache_write_patch_addr),
    .patch_data(icache_write_patch_data),
    .patch_be(icache_write_patch_be),
    .patch_valid(icache_write_patch_valid),
    .invalidate_addr(icache_invalidate_addr),
    .invalidate_valid(icache_invalidate_valid),
    .flush_req(cf_start_r),
    .flush_busy(icache_flush_busy),
    .flush_done(icache_flush_done),
    .cache_enable(1'b1),
    .cpu_no_alloc(icache_req_is_no_alloc)
);

endmodule
