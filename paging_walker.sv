//
// Page Table Walker for 80386 Paging Unit
// Two-level page table walk: Page Directory Entry (PDE) -> Page Table Entry (PTE)
//
`timescale 1ns/1ns

module paging_walker
    import z486_pkg::*;
(
    input               clk,
    input               reset_n,

    // Request interface
    input               walk_request,
    input        [31:0] linear_addr,
    input               is_write,
    input        [1:0]  cpl,            // Current privilege level
    input        [31:0] cr3,            // Page directory base register
    input               wp_enable,      // CR0.WP - write protect

    // Result interface
    output reg          walk_done,
    output reg          walk_fault,
    output reg   [2:0]  fault_code,     // [2]=U, [1]=W, [0]=P
    output reg   [19:0] result_pfn,
    output reg          result_writable,
    output reg          result_user,
    output reg          result_dirty,
    output reg          result_pcd,     // PTE.PCD: the page's data/code is uncacheable
    output reg          result_pwt,     // PTE.PWT (reported through TR7 only)

    // Memory interface for page table reads and write-backs
    output reg          mem_rd,
    output reg          mem_wr,
    output reg   [31:0] mem_addr,
    output reg   [31:0] mem_wdata,
    output reg          mem_pcd,        // PCD for this table access (CR3 for the PDE, PDE for the PTE)
    output reg          mem_locked,     // Locked read (LOCK#): bypass the L1, read memory
    output reg          ad_lock,        // Hold LOCK# for an A/D read-modify-write
    input        [31:0] mem_data,
    input               mem_ready,
    // PC-98 debug taps: the last directory and table entries read
    output      [31:0] dbg_pde,
    output      [31:0] dbg_pte
);

// Page walk state machine
typedef enum logic [3:0] {
    PW_IDLE,
    PW_READ_PDE,        // Issue PDE read
    PW_WAIT_PDE,        // Wait for PDE data
    PW_READ_PTE,        // Issue PTE read
    PW_WAIT_PTE,        // Wait for PTE data
    PW_CHECK_PERM,      // Check permissions before write-back
    PW_WRITE_PDE,       // Write back PDE with ACCESSED bit
    PW_WAIT_WR_PDE,     // Wait for PDE write completion
    PW_WRITE_PTE,       // Write back PTE with ACCESSED (+ DIRTY if write)
    PW_WAIT_WR_PTE,     // Wait for PTE write completion
    PW_DONE,            // Walk complete (success, after write-back)
    PW_FAULT,           // Walk complete (fault, no write-back)
    PW_LOCK_PDE,        // Issue locked re-read of the PDE before setting A
    PW_WAIT_LOCK_PDE,
    PW_LOCK_PTE,        // Issue locked re-read of the PTE before setting A/D
    PW_WAIT_LOCK_PTE
} pw_state_t;

pw_state_t state, next_state;

// Latched request parameters
reg [31:0] saved_linear;
reg        saved_is_write;
reg [1:0]  saved_cpl;
reg [31:0] saved_cr3;
reg        saved_wp;

// Page directory entry and page table entry
reg [31:0] pde;
reg [31:0] pte;
// A 486 sets A/D with a locked read-modify-write.  The entries above are first
// read unlocked (possibly from the L1); an entry that needs an A/D update is
// re-read with a locked read and re-checked before it is written, so an
// external write between the walk and the update is neither lost nor
// overridden.  *_fresh marks an entry that holds the locked read's value,
// LOCK# being held (ad_lock) from that read until the walk ends.
reg        pde_fresh;
reg        pte_fresh;

// Debug taps: the two entries the current (or last) walk read.
assign dbg_pde = pde;
assign dbg_pte = pte;

localparam bit TRACE_PAGING_EN = 1'b0;

// Linear address components
wire [9:0] dir_index   = saved_linear[31:22];   // Page directory index
wire [9:0] table_index = saved_linear[21:12];   // Page table index

// PDE address = CR3[31:12] | dir_index << 2
wire [31:0] pde_addr = {saved_cr3[31:12], dir_index, 2'b00};

// PTE address = PDE[31:12] | table_index << 2
wire [31:0] pte_addr = {pde[31:12], table_index, 2'b00};

// Permission checking
wire pde_present  = pde[PTE_P];
wire pde_writable = pde[PTE_RW];
wire pde_user     = pde[PTE_US];

wire pte_present  = pte[PTE_P];
wire pte_writable = pte[PTE_RW];
wire pte_user     = pte[PTE_US];
wire pte_dirty    = pte[PTE_D];
wire pte_accessed = pte[PTE_A];

// Combined permissions (most restrictive of PDE and PTE)
wire combined_writable = pde_writable & pte_writable;
wire combined_user     = pde_user & pte_user;

// Access checking
wire is_user_mode = (saved_cpl == 2'd3);
wire user_access_ok = !is_user_mode || combined_user;
wire write_access_ok = !saved_is_write ||
                       combined_writable ||
                       (!is_user_mode && !saved_wp);

// A/D write-back elision.  The 486 only needs the CPU to set A before the
// access and D before a write; re-storing an entry whose bits are already set
// writes the identical dword, which is unobservable in RAM but issues a
// spurious store when the page table lives in an uncached/DIRECT device
// window or in read-only memory.  Skip a write-back whose bits are unchanged.
// A-set/D-clear on a write access is the one case that still needs the entry
// written (D must be set).
wire pde_update_required = !pde[PTE_A];
wire pte_update_required = !pte[PTE_A] || (saved_is_write && !pte[PTE_D]);

// State machine
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= PW_IDLE;
        saved_linear <= 32'h0;
        saved_is_write <= 1'b0;
        saved_cpl <= 2'b00;
        saved_cr3 <= 32'h0;
        saved_wp <= 1'b0;
        pde <= 32'h0;
        pte <= 32'h0;
        pde_fresh <= 1'b0;
        pte_fresh <= 1'b0;
        ad_lock <= 1'b0;
    end else begin
        state <= next_state;

        // LOCK# from the first locked read until the walk ends.
        if (next_state == PW_LOCK_PDE || next_state == PW_LOCK_PTE)
            ad_lock <= 1'b1;
        else if (state == PW_DONE || state == PW_FAULT)
            ad_lock <= 1'b0;

        // Latch request parameters at start
        if (state == PW_IDLE && walk_request) begin
            saved_linear <= linear_addr;
            saved_is_write <= is_write;
            saved_cpl <= cpl;
            saved_cr3 <= cr3;
            saved_wp <= wp_enable;
            pde_fresh <= 1'b0;
            pte_fresh <= 1'b0;
        end

        // Latch PDE when memory returns
        if (state == PW_WAIT_PDE && mem_ready) begin
            pde <= mem_data;
        end

        // Latch PTE when memory returns
        if (state == PW_WAIT_PTE && mem_ready) begin
            pte <= mem_data;
        end

        // Locked re-reads replace the entry and are re-checked.  The PTE is
        // re-read (unlocked) after a locked PDE read, which may have moved
        // the page table.
        if (state == PW_WAIT_LOCK_PDE && mem_ready) begin
            pde <= mem_data;
            pde_fresh <= 1'b1;
        end
        if (state == PW_WAIT_LOCK_PTE && mem_ready) begin
            pte <= mem_data;
            pte_fresh <= 1'b1;
        end

        // A written entry now holds its A/D bits; the next update of the
        // other entry (or a re-check) must not repeat it.
        if (state == PW_WAIT_WR_PDE && mem_ready) begin
            pde[PTE_A] <= 1'b1;
            pde_fresh <= 1'b0;
        end
        if (state == PW_WAIT_WR_PTE && mem_ready) begin
            pte[PTE_A] <= 1'b1;
            if (saved_is_write)
                pte[PTE_D] <= 1'b1;
            pte_fresh <= 1'b0;
        end
    end
end

// Next state logic
always_comb begin
    next_state = state;

    case (state)
        PW_IDLE: begin
            if (walk_request)
                next_state = PW_READ_PDE;
        end

        PW_READ_PDE: begin
            next_state = PW_WAIT_PDE;
        end

        PW_WAIT_PDE: begin
            if (mem_ready) begin
                if (!mem_data[PTE_P])
                    next_state = PW_FAULT;      // PDE not present
                else
                    next_state = PW_READ_PTE;   // PDE OK, read PTE
            end
        end

        PW_READ_PTE: begin
            next_state = PW_WAIT_PTE;
        end

        PW_WAIT_PTE: begin
            if (mem_ready) begin
                if (!mem_data[PTE_P])
                    next_state = PW_FAULT;      // PTE not present
                else
                    next_state = PW_CHECK_PERM; // Check permissions before write-back
            end
        end

        PW_CHECK_PERM: begin
            // Permission check: only write back A/D bits if access is
            // permitted.  Presence is re-checked for a locked re-read.
            if (!pde_present || !pte_present || !user_access_ok || !write_access_ok)
                next_state = PW_FAULT;          // Fault, no write-back
            else if (pde_update_required)       // Permissions OK, set A
                next_state = pde_fresh ? PW_WRITE_PDE : PW_LOCK_PDE;
            else if (pte_update_required)       // PDE unchanged, set PTE A/D
                next_state = pte_fresh ? PW_WRITE_PTE : PW_LOCK_PTE;
            else
                next_state = PW_DONE;           // Nothing to update
        end

        PW_LOCK_PDE: begin
            next_state = PW_WAIT_LOCK_PDE;
        end

        PW_WAIT_LOCK_PDE: begin
            if (mem_ready) begin
                if (!mem_data[PTE_P])
                    next_state = PW_FAULT;      // PDE became not present
                else
                    next_state = PW_READ_PTE;   // re-read the PTE, re-check
            end
        end

        PW_LOCK_PTE: begin
            next_state = PW_WAIT_LOCK_PTE;
        end

        PW_WAIT_LOCK_PTE: begin
            if (mem_ready)
                next_state = PW_CHECK_PERM;     // re-check the fresh PTE
        end

        PW_WRITE_PDE: begin
            next_state = PW_WAIT_WR_PDE;
        end

        PW_WAIT_WR_PDE: begin
            if (mem_ready)
                next_state = pte_update_required ? PW_LOCK_PTE : PW_DONE;
        end

        PW_WRITE_PTE: begin
            next_state = PW_WAIT_WR_PTE;
        end

        PW_WAIT_WR_PTE: begin
            if (mem_ready)
                next_state = PW_DONE;
        end

        PW_DONE: begin
            next_state = PW_IDLE;
        end

        PW_FAULT: begin
            next_state = PW_IDLE;
        end

        default: next_state = PW_IDLE;
    endcase
end

// Output logic
always_comb begin
    // Defaults
    walk_done = 1'b0;
    walk_fault = 1'b0;
    fault_code = 3'b000;
    mem_rd = 1'b0;
    mem_wr = 1'b0;
    mem_addr = 32'h0;
    mem_wdata = 32'h0;
    mem_locked = 1'b0;
    result_pfn = 20'h0;
    result_writable = 1'b0;
    result_user = 1'b0;
    result_dirty = 1'b0;
    result_pcd = 1'b0;
    result_pwt = 1'b0;
    // 486: CR3.PCD qualifies the page-directory access, PDE.PCD the page-table
    // access (the PTE's own PCD qualifies the translated page).
    mem_pcd = (state == PW_READ_PDE || state == PW_WAIT_PDE ||
               state == PW_LOCK_PDE || state == PW_WAIT_LOCK_PDE ||
               state == PW_WRITE_PDE || state == PW_WAIT_WR_PDE)
            ? saved_cr3[PTE_PCD] : pde[PTE_PCD];

    case (state)
        PW_READ_PDE: begin
            mem_rd = 1'b1;
            mem_addr = pde_addr;
        end

        PW_WAIT_PDE: begin
            // Hold request intent stable through the response cycle. The
            // paging-unit pending bit prevents reissue, so feeding mem_ready
            // back into these outputs only creates a cache-response control
            // path into unrelated request registers.
            mem_rd = 1'b1;
            mem_addr = pde_addr;
        end

        PW_READ_PTE: begin
            mem_rd = 1'b1;
            mem_addr = pte_addr;
        end

        PW_WAIT_PTE: begin
            mem_rd = 1'b1;
            mem_addr = pte_addr;
        end

        PW_LOCK_PDE, PW_WAIT_LOCK_PDE: begin
            mem_rd = 1'b1;
            mem_locked = 1'b1;
            mem_addr = pde_addr;
        end

        PW_LOCK_PTE, PW_WAIT_LOCK_PTE: begin
            mem_rd = 1'b1;
            mem_locked = 1'b1;
            mem_addr = pte_addr;
        end

        PW_CHECK_PERM: begin
            // Pure transition state — walk_done/walk_fault signaled in PW_FAULT or PW_DONE
        end

        PW_WRITE_PDE: begin
            mem_wr = 1'b1;
            mem_addr = pde_addr;
            mem_wdata = pde | (32'h1 << PTE_A);  // Set ACCESSED bit
        end

        PW_WAIT_WR_PDE: begin
            mem_wr = 1'b1;
            mem_addr = pde_addr;
            mem_wdata = pde | (32'h1 << PTE_A);
        end

        PW_WRITE_PTE: begin
            mem_wr = 1'b1;
            mem_addr = pte_addr;
            // Set ACCESSED, and DIRTY if this is a write access
            mem_wdata = pte | (32'h1 << PTE_A) | (saved_is_write ? (32'h1 << PTE_D) : 32'h0);
        end

        PW_WAIT_WR_PTE: begin
            mem_wr = 1'b1;
            mem_addr = pte_addr;
            mem_wdata = pte | (32'h1 << PTE_A) |
                        (saved_is_write ? (32'h1 << PTE_D) : 32'h0);
        end

        PW_DONE: begin
            // Walk succeeded with write-back complete
            walk_done = 1'b1;
            result_pfn = pte[31:12];
            result_writable = combined_writable;
            result_user = combined_user;
            result_dirty = pte_dirty || saved_is_write;  // Updated after write-back
            result_pcd = pte[PTE_PCD];
            result_pwt = pte[PTE_PWT];
        end

        PW_FAULT: begin
            walk_done = 1'b1;
            walk_fault = 1'b1;
            // Determine fault code based on what failed
            if (!pde_present) begin
                fault_code[PF_P] = 1'b0;  // PDE not present
            end else if (!pte_present) begin
                fault_code[PF_P] = 1'b0;  // PTE not present
            end else begin
                fault_code[PF_P] = 1'b1;  // Protection violation
            end
            fault_code[PF_W] = saved_is_write;
            fault_code[PF_U] = is_user_mode;

        end

        default: ;
    endcase
end

endmodule
