`timescale 1ns/1ps

// Directed test for paging_tlb: a page served from the VIPT sidecar stays in the
// four-way TLB while it is in use.
//
// A 486 refreshes a page's pseudo-LRU state on every access that uses it, so a
// page referenced between installs of other pages of its set is never the
// victim. The sidecar serves many reads without the main lookup port ever
// seeing them; when its hits did not refresh the main TLB's replacement state,
// such a page aged out of the main TLB while still in use, and the next access
// that needed the main TLB walked again. On the PC-9821 core that walk ran with
// A20 masked and VEM486 took #PF at 0xFD880 under HSB, which the real 486 never
// does (the owner's Xe10, V86PF W/X/G..K captures).
//
// The bench installs P, points the main lookup port at an unrelated set, then
// serves P once from the sidecar before each install of Q1..Q4 (all in P's set)
// and finally checks that P is still in the main TLB. Without the refresh the
// fourth install evicts P (its way is the pseudo-LRU victim, having never been
// touched since it was installed).

`default_nettype none

module tb_paging_tlb_lru;
  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg reset_n = 1'b0;

  reg  [31:0] linear_addr = 32'h0;
  wire        hit;
  wire [31:0] physical_addr;
  wire        writable, user, dirty, is_vga_mem, is_pcd;
  reg         vipt_preread = 1'b0;
  reg  [31:0] vipt_linear_addr = 32'h0;
  wire        vipt_hit;
  wire [31:0] vipt_physical_addr;
  wire        vipt_writable, vipt_user, vipt_dirty, vipt_is_vga_mem;
  reg         update_valid = 1'b0;
  reg  [19:0] update_vpn = 20'h0;
  reg  [19:0] update_pfn = 20'h0;

  /* verilator lint_off PINCONNECTEMPTY */
  paging_tlb dut (
    .clk(clk), .reset_n(reset_n),
    .linear_addr(linear_addr), .hit(hit), .physical_addr(physical_addr),
    .writable(writable), .user(user), .dirty(dirty),
    .is_vga_mem(is_vga_mem), .is_pcd(is_pcd),
    .linear_addr_live(32'h0), .live_hit(), .live_physical_addr(),
    .live_writable(), .live_user(), .live_dirty(), .live_is_vga_mem(),
    .vipt_preread(vipt_preread), .vipt_linear_addr(vipt_linear_addr),
    .vipt_hit(vipt_hit), .vipt_physical_addr(vipt_physical_addr),
    .vipt_writable(vipt_writable), .vipt_user(vipt_user), .vipt_dirty(vipt_dirty),
    .vipt_is_vga_mem(vipt_is_vga_mem),
    .vipt_refill_valid(1'b0), .vipt_refill_linear(32'h0), .vipt_refill_pfn(20'h0),
    .vipt_refill_writable(1'b0), .vipt_refill_user(1'b0), .vipt_refill_dirty(1'b0),
    .vipt_refill_pcd(1'b0),
    .update_valid(update_valid), .update_vpn(update_vpn), .update_pfn(update_pfn),
    .update_writable(1'b1), .update_user(1'b1), .update_dirty(1'b1),
    .update_pcd(1'b0), .update_pwt(1'b0),
    .invalidate_all(1'b0), .invalidate_page(1'b0), .invalidate_vpn(20'h0),
    .tlbt_req(1'b0), .tlbt_tr6(32'h0), .tlbt_tr7(32'h0),
    .tlbt_done(), .tlbt_lookup_done(), .tlbt_tr6_out(), .tlbt_tr7_out()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Set 5 = VPN[2:0] == 5. OTHER is set 0, so the main lookup port's own hits
  // never touch set 5 while the sidecar serves P.
  localparam [31:0] P     = 32'h0002_5000;
  localparam [31:0] OTHER = 32'h0001_0000;
  localparam [31:0] Q1 = 32'h0002_D000, Q2 = 32'h0003_5000,
                    Q3 = 32'h0003_D000, Q4 = 32'h0004_5000;

  integer errors = 0;

  // A walker refill: paging_unit always presents the walked page on the lookup
  // port (update_vpn == the registered lookup VPN).
  task automatic install(input [31:0] addr);
    linear_addr = addr;
    @(posedge clk); #1;
    update_valid = 1'b1; update_vpn = addr[31:12]; update_pfn = addr[31:12];
    @(posedge clk); #1;
    update_valid = 1'b0;
    linear_addr = OTHER;
    @(posedge clk); #1;
  endtask

  // One sidecar-served read of addr: the preread, then the cycle it matches.
  task automatic sidecar_read(input [31:0] addr);
    vipt_preread = 1'b1; vipt_linear_addr = addr;
    @(posedge clk); #1;
    vipt_preread = 1'b0;
    if (!vipt_hit) begin
      $display("FAIL: the sidecar does not hold %08x", addr);
      errors = errors + 1;
    end
    @(posedge clk); #1;
  endtask

  initial begin
    repeat (3) @(posedge clk);
    reset_n = 1'b1;
    @(posedge clk); #1;
    linear_addr = OTHER;
    install(OTHER);                 // the lookup port's parking page, set 0

    install(P);
    sidecar_read(P); install(Q1);
    sidecar_read(P); install(Q2);
    sidecar_read(P); install(Q3);
    sidecar_read(P); install(Q4);
    sidecar_read(P);

    linear_addr = P;
    #1;
    if (!hit) begin
      $display("FAIL: P (%08x), read from the sidecar before every install, was evicted from the four-way TLB", P);
      errors = errors + 1;
    end
    // Q1 was the least recently used page of the set when Q4 arrived.
    linear_addr = Q1;
    #1;
    if (hit) begin
      $display("FAIL: Q1 should have been the victim of Q4's install");
      errors = errors + 1;
    end

    if (errors == 0) $display("PAGING TLB TEST PASS");
    else             $fatal(1, "PAGING TLB TEST FAIL (%0d error(s))", errors);
    $finish;
  end
endmodule
