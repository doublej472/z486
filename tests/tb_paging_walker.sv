`timescale 1ns/1ps

// Directed test for paging_walker: the 486 A/D write-back case table.
//
// paging_walker only writes back the PDE and PTE when the hardware must change
// an Accessed/Dirty bit.  Re-storing an entry whose bits are already set writes
// the identical dword -- unobservable in RAM, but a spurious store when the
// page table lives in an uncached/DIRECT device window or in read-only memory
// -- so this bench pins exactly which entries are written, with which data, for
// every combination of A/D state, access type, privilege and fault.

`default_nettype none

module tb_paging_walker;
  import z486_pkg::*;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg reset_n = 1'b0;

  // ==== DUT I/O ====
  reg         walk_request = 1'b0;
  reg  [31:0] linear_addr = 32'h0;
  reg         req_is_write = 1'b0;
  reg  [1:0]  req_cpl = 2'b00;
  reg  [31:0] req_cr3 = 32'h0000_2000;
  reg         req_wp = 1'b0;
  wire        walk_done;
  wire        walk_fault;
  wire  [2:0] fault_code;
  wire [19:0] result_pfn;
  wire        result_writable;
  wire        result_user;
  wire        result_dirty;
  wire        mem_rd;
  wire        mem_wr;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire        mem_locked;
  wire        ad_lock;
  reg  [31:0] mem_data = 32'h0;
  reg         mem_ready = 1'b0;

  paging_walker dut (
    .clk(clk),
    .reset_n(reset_n),
    .walk_request(walk_request),
    .linear_addr(linear_addr),
    .is_write(req_is_write),
    .cpl(req_cpl),
    .cr3(req_cr3),
    .wp_enable(req_wp),
    .walk_done(walk_done),
    .walk_fault(walk_fault),
    .fault_code(fault_code),
    .result_pfn(result_pfn),
    .result_writable(result_writable),
    .result_user(result_user),
    .result_dirty(result_dirty),
    .result_pcd(),
    .mem_rd(mem_rd),
    .mem_wr(mem_wr),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_pcd(),
    .mem_locked(mem_locked),
    .ad_lock(ad_lock),
    .mem_data(mem_data),
    .mem_ready(mem_ready)
  );

  // ==== Page-table memory: 64 KB, indexed by addr[15:2] ====
  // PD at 0x2000 (CR3), the walked page table at 0x3000.
  reg [31:0] mem [0:16383];

  function automatic int mi(input [31:0] a);
    mi = a[15:2];
  endfunction

  task automatic mem_put(input [31:0] a, input [31:0] v);
    mem[mi(a)] = v;
  endtask

  function automatic [31:0] mem_get(input [31:0] a);
    mem_get = mem[mi(a)];
  endfunction

  // ==== Write-back log ====
  localparam int MAXW = 8;
  int        wr_count;
  reg [31:0] wr_addr [0:MAXW-1];
  reg [31:0] wr_data [0:MAXW-1];

  // ==== External master model ====
  // When armed, the first unlocked read of mut_addr is followed by an external
  // write of mut_val to it, i.e. the entry changes between the walk's read
  // and its A/D update.  An A/D write must come from a locked read of the
  // same entry in this walk, with LOCK# (ad_lock) held.
  bit        mut_armed = 1'b0;
  reg [31:0] mut_addr;
  reg [31:0] mut_val;
  int        locked_rd_count;
  reg [31:0] locked_rd_addr [0:MAXW-1];

  // ==== One-cycle-latency slave; logs every accepted write ====
  reg pending;
  always @(posedge clk) begin
    if (!reset_n) begin
      pending  <= 1'b0;
      mem_ready <= 1'b0;
    end else begin
      mem_ready <= 1'b0;
      if (!(mem_rd || mem_wr)) begin
        pending <= 1'b0;
      end else if (!pending) begin
        pending   <= 1'b1;
        mem_ready <= 1'b1;
        mem_data  <= mem[mi(mem_addr)];
        if (mem_rd && mem_locked) begin
          if (!ad_lock) begin
            $display("PAGING WALKER FAIL [%s]: locked read without LOCK#",
                     case_name);
            $fatal(1);
          end
          if (locked_rd_count < MAXW)
            locked_rd_addr[locked_rd_count] = mem_addr;
          locked_rd_count = locked_rd_count + 1;
        end else if (mem_rd && mut_armed && mem_addr == mut_addr) begin
          mut_armed = 1'b0;
          mem[mi(mem_addr)] <= mut_val;
        end
        if (mem_wr) begin
          bit seen = 1'b0;
          for (int i = 0; i < locked_rd_count && i < MAXW; i = i + 1)
            if (locked_rd_addr[i] == mem_addr) seen = 1'b1;
          if (!seen || !ad_lock) begin
            $display("PAGING WALKER FAIL [%s]: A/D write %08x without a locked read/LOCK#",
                     case_name, mem_addr);
            $fatal(1);
          end
          if (wr_count < MAXW) begin
            wr_addr[wr_count] = mem_addr;
            wr_data[wr_count] = mem_wdata;
          end
          wr_count = wr_count + 1;
          mem[mi(mem_addr)] <= mem_wdata;
        end
      end else begin
        pending <= 1'b0;
      end
    end
  end

  // ==== Walk driver ====
  // Result fields are combinational in PW_DONE / PW_FAULT, so they are
  // captured in the completion cycle.
  string case_name;
  int    timeout;
  bit         got_done, got_fault;
  bit  [2:0]  got_code;
  bit [19:0]  got_pfn;
  bit         got_writable, got_user, got_dirty;

  task automatic start_walk(input [31:0] lin, input bit wr, input [1:0] cpl,
                            input bit wp);
    wr_count = 0;
    locked_rd_count = 0;
    linear_addr = lin;
    req_is_write = wr;
    req_cpl = cpl;
    req_wp = wp;
    walk_request = 1'b1;
    @(negedge clk);
    walk_request = 1'b0;
    timeout = 0;
    while (!walk_done) begin
      @(negedge clk);
      timeout = timeout + 1;
      if (timeout > 80) begin
        $display("PAGING WALKER FAIL [%s]: timeout", case_name);
        $fatal(1);
      end
    end
    got_done     = walk_done;
    got_fault    = walk_fault;
    got_code     = fault_code;
    got_pfn      = result_pfn;
    got_writable = result_writable;
    got_user     = result_user;
    got_dirty    = result_dirty;
    @(negedge clk);
    mut_armed = 1'b0;
  endtask

  task automatic expect_writes(input int n, input [31:0] a0, input [31:0] d0,
                               input [31:0] a1, input [31:0] d1);
    if (wr_count !== n) begin
      $display("PAGING WALKER FAIL [%s]: %0d write-backs, expected %0d",
               case_name, wr_count, n);
      for (int i = 0; i < wr_count && i < MAXW; i = i + 1)
        $display("   wrote %08x <= %08x", wr_addr[i], wr_data[i]);
      $fatal(1);
    end
    if (n > 0 && (wr_addr[0] !== a0 || wr_data[0] !== d0)) begin
      $display("PAGING WALKER FAIL [%s]: first  write %08x <= %08x, expected %08x <= %08x",
               case_name, wr_addr[0], wr_data[0], a0, d0);
      $fatal(1);
    end
    if (n > 1 && (wr_addr[1] !== a1 || wr_data[1] !== d1)) begin
      $display("PAGING WALKER FAIL [%s]: second write %08x <= %08x, expected %08x <= %08x",
               case_name, wr_addr[1], wr_data[1], a1, d1);
      $fatal(1);
    end
  endtask

  task automatic expect_no_fault();
    if (got_fault) begin
      $display("PAGING WALKER FAIL [%s]: unexpected fault code=%b", case_name,
               got_code);
      $fatal(1);
    end
  endtask

  task automatic expect_fault(input [2:0] code);
    if (!got_fault) begin
      $display("PAGING WALKER FAIL [%s]: expected fault code=%b, walked OK",
               case_name, code);
      $fatal(1);
    end
    if (got_code !== code) begin
      $display("PAGING WALKER FAIL [%s]: fault code=%b, expected %b",
               case_name, got_code, code);
      $fatal(1);
    end
    if (wr_count !== 0) begin
      $display("PAGING WALKER FAIL [%s]: %0d write-backs on a faulting walk",
               case_name, wr_count);
      $fatal(1);
    end
  endtask

  // PDE at CR3 base 0x2000 (dir index 0), PTE at 0x3000 (table index 0).
  localparam [31:0] PDE_ADDR  = 32'h0000_2000;
  localparam [31:0] PTE_ADDR  = 32'h0000_3000;
  localparam [31:0] PT_FRAME  = 32'h0000_3000;
  localparam [31:0] WALK_LIN  = 32'h0000_0004;
  localparam [31:0] FRAME     = 32'h0045_6000;
  // entry bits: P|RW|US, with the caller's A/D
  function automatic [31:0] entry(input bit rw, input bit us, input bit a,
                                  input bit d);
    entry = 32'h1
          | (rw ? (32'h1 << PTE_RW) : 32'h0)
          | (us ? (32'h1 << PTE_US) : 32'h0)
          | (a  ? (32'h1 << PTE_A)  : 32'h0)
          | (d  ? (32'h1 << PTE_D)  : 32'h0);
  endfunction

  function automatic [31:0] pte_val(input bit a, input bit d);
    pte_val = FRAME | entry(1'b1, 1'b1, a, d);
  endfunction

  function automatic [31:0] pde_val(input bit rw, input bit us, input bit a);
    pde_val = PT_FRAME | entry(rw, us, a, 1'b0);
  endfunction

  task automatic setup(input [31:0] pde_bits, input [31:0] pte_bits);
    mem_put(PDE_ADDR, PT_FRAME | pde_bits);
    mem_put(PTE_ADDR, FRAME | pte_bits);
  endtask

  function automatic [31:0] with_a(input [31:0] v);
    with_a = v | (32'h1 << PTE_A);
  endfunction

  function automatic [31:0] with_ad(input [31:0] v);
    with_ad = v | (32'h1 << PTE_A) | (32'h1 << PTE_D);
  endfunction

  // Not-present entry with RW/US set, to prove the fault path itself is taken.
  localparam [31:0] NOT_PRESENT = 32'h0000_0006;

  initial begin
    for (int i = 0; i < 16384; i = i + 1) mem[i] = 32'h0;
    repeat (4) @(posedge clk);
    reset_n = 1'b1;
    repeat (4) @(posedge clk);

    // ---- A/D write-back case table ----------------------------------
    // 1. A clear everywhere, load: both entries written with A set.
    case_name = "A clear / load";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(2, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  PTE_ADDR, pte_val(1'b1, 1'b0));

    // 2. A clear everywhere, store: A set, D set.
    case_name = "A clear / store";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(2, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  PTE_ADDR, pte_val(1'b1, 1'b1));

    // 3. PDE A clear, PTE A set, load: only the PDE is refreshed.
    case_name = "PDE A clear / PTE A set / load";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b0));
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  32'h0, 32'h0);

    // 4. Everything already set, load: no page-table store at all.
    case_name = "A set / D set / load";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b1));
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(0, 32'h0, 32'h0, 32'h0, 32'h0);
    if (got_dirty !== 1'b1 || got_pfn !== FRAME[31:12] ||
        got_writable !== 1'b1 || got_user !== 1'b1) begin
      $display("PAGING WALKER FAIL [%s]: results pfn=%05x w=%b u=%b d=%b",
               case_name, got_pfn, got_writable, got_user, got_dirty);
      $fatal(1);
    end

    // 5. A set, D clear, store: the PTE must still be written to set D.
    case_name = "A set / D clear / store";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PTE_ADDR, pte_val(1'b1, 1'b1), 32'h0, 32'h0);
    if (got_dirty !== 1'b1) begin
      $display("PAGING WALKER FAIL [%s]: result_dirty=%b", case_name,
               got_dirty);
      $fatal(1);
    end

    // 6. A set, D set, store: nothing changes, no store.
    case_name = "A set / D set / store";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b1));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(0, 32'h0, 32'h0, 32'h0, 32'h0);

    // 7. PDE A clear, PTE A/D set, store: only the PDE is refreshed.
    case_name = "PDE A clear / PTE A+D set / store";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b1));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  32'h0, 32'h0);

    // 8. PDE A clear, PTE A set/D clear, store: PDE then PTE, in that order.
    case_name = "PDE A clear / PTE A set / store";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(2, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  PTE_ADDR, pte_val(1'b1, 1'b1));

    // 9. PTE A clear, D set, load: A must be set (D stays set).
    case_name = "PTE A clear / D set / load";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b1));
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PTE_ADDR, pte_val(1'b1, 1'b1), 32'h0, 32'h0);

    // 10. PDE A set, PTE A clear, store: PTE written with A and D.
    case_name = "PTE A clear / store";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PTE_ADDR, pte_val(1'b1, 1'b1), 32'h0, 32'h0);

    // 11. Read-only page, supervisor write with CR0.WP=1: protection fault,
    //     and no A/D write-back before the fault is taken.
    case_name = "read-only / WP=1 supervisor store";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b0, 1'b1, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b1);
    expect_fault(3'b011);   // P=1 (protection), W=1, U=0

    // 12. Same read-only page with CR0.WP=0: supervisor writes are allowed
    //     and still set A and D.
    case_name = "read-only / WP=0 supervisor store";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b0, 1'b1, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(2, PDE_ADDR, pde_val(1'b1, 1'b1, 1'b1),
                  PTE_ADDR, with_ad(FRAME | entry(1'b0, 1'b1, 1'b0, 1'b0)));
    if (got_writable !== 1'b0 || got_dirty !== 1'b1) begin
      $display("PAGING WALKER FAIL [%s]: w=%b d=%b", case_name,
               got_writable, got_dirty);
      $fatal(1);
    end

    // 13. User access to a supervisor page: fault, no write-back.
    case_name = "user mode / supervisor page";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b0, 1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b0, 2'd3, 1'b0);
    expect_fault(3'b101);   // P=1 protection, W=0, U=1

    // 14. PDE not present: fault with P=0, no write-back.
    case_name = "PDE not present";
    mem_put(PDE_ADDR, NOT_PRESENT);
    mem_put(PTE_ADDR, pte_val(1'b0, 1'b0));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_fault(3'b010);   // P=0, W=1, U=0

    // 15. PTE not present: fault with P=0, no write-back.
    case_name = "PTE not present";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    mem_put(PTE_ADDR, NOT_PRESENT);
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_fault(3'b000);   // P=0, W=0, U=0

    // 16. The user/writable result bits are the AND of both levels.
    case_name = "combined permissions";
    setup(entry(1'b1, 1'b0, 1'b1, 1'b0), entry(1'b0, 1'b1, 1'b1, 1'b1));
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(0, 32'h0, 32'h0, 32'h0, 32'h0);
    if (got_user !== 1'b0 || got_writable !== 1'b0 ||
        got_pfn !== FRAME[31:12]) begin
      $display("PAGING WALKER FAIL [%s]: pfn=%05x w=%b u=%b", case_name,
               got_pfn, got_writable, got_user);
      $fatal(1);
    end

    // 17. Second walk to the same page with everything set performs no store,
    //     i.e. a TLB refill of an already-A/D entry is bus-silent.
    case_name = "repeat walk, A/D set";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b1));
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(0, 32'h0, 32'h0, 32'h0, 32'h0);

    // ---- A/D update is a locked read-modify-write --------------------
    // 18. An external write lands on the PTE after the walk read it: the
    //     update merges it (AVL bit 9 survives).
    case_name = "external PTE write before A/D update";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    mut_addr = PTE_ADDR;
    mut_val = pte_val(1'b0, 1'b0) | 32'h200;
    mut_armed = 1'b1;
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PTE_ADDR, pte_val(1'b1, 1'b1) | 32'h200, 32'h0, 32'h0);

    // 19. The PTE is made not present before the update: #PF (P=0), and the
    //     entry is not written.
    case_name = "PTE made not present before A/D update";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b0, 1'b0));
    mut_addr = PTE_ADDR;
    mut_val = NOT_PRESENT;
    mut_armed = 1'b1;
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b0);
    expect_fault(3'b010);
    if (mem_get(PTE_ADDR) !== NOT_PRESENT) begin
      $display("PAGING WALKER FAIL [%s]: PTE=%08x", case_name, mem_get(PTE_ADDR));
      $fatal(1);
    end

    // 20. The PTE is made read-only before a WP=1 supervisor store's update:
    //     protection #PF, no write.
    case_name = "PTE made read-only before A/D update";
    setup(entry(1'b1, 1'b1, 1'b1, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b0));
    mut_addr = PTE_ADDR;
    mut_val = FRAME | entry(1'b0, 1'b1, 1'b1, 1'b0);
    mut_armed = 1'b1;
    start_walk(WALK_LIN, 1'b1, 2'd0, 1'b1);
    expect_fault(3'b011);

    // 21. The PDE is moved to another page table before its A update: the
    //     walk uses the new table.
    case_name = "PDE moved before A update";
    setup(entry(1'b1, 1'b1, 1'b0, 1'b0), entry(1'b1, 1'b1, 1'b1, 1'b1));
    mem_put(32'h0000_4000, 32'h0078_9000 | entry(1'b1, 1'b1, 1'b1, 1'b1));
    mut_addr = PDE_ADDR;
    mut_val = 32'h0000_4000 | entry(1'b1, 1'b1, 1'b0, 1'b0);
    mut_armed = 1'b1;
    start_walk(WALK_LIN, 1'b0, 2'd0, 1'b0);
    expect_no_fault();
    expect_writes(1, PDE_ADDR, 32'h0000_4000 | entry(1'b1, 1'b1, 1'b1, 1'b0),
                  32'h0, 32'h0);
    if (got_pfn !== 20'h00789) begin
      $display("PAGING WALKER FAIL [%s]: pfn=%05x", case_name, got_pfn);
      $fatal(1);
    end

    $display("PAGING WALKER TEST PASS (%0d cases)", 21);
    $finish;
  end
endmodule

`default_nettype wire
