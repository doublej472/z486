// Unit test for the portable memory-map / cache-classification template
// (z486_cache_map_pkg): pins the PC/AT default and the PC-98 preset windows.
`timescale 1ns/1ns
`include "z486_pc98_preset.svh"
import z486_cache_map_pkg::*;

module tb_memmap_template;
    integer errors = 0;

    task automatic check_class(input string name, input z486_cache_class_t got,
                               input z486_cache_class_t want);
        if (got !== want) begin
            $display("FAIL %s: got class %0d want %0d", name, got, want);
            errors++;
        end else begin
            $display("ok   %s", name);
        end
    endtask

    task automatic check_bit(input string name, input logic got, input logic want);
        if (got !== want) begin
            $display("FAIL %s: got %b want %b", name, got, want);
            errors++;
        end else begin
            $display("ok   %s", name);
        end
    endtask

    task automatic check_word(input string name, input logic [31:0] got,
                              input logic [31:0] want);
        if (got !== want) begin
            $display("FAIL %s: got %h want %h", name, got, want);
            errors++;
        end else begin
            $display("ok   %s", name);
        end
    endtask

    // ------------------------------------------------------------------
    // Reduced-predicate equivalence against the plain magnitude reference.
    // The package folds constant windows (masked equality / dropped low-bit
    // compares); this pins it bit-exact for aligned, unaligned, single-
    // address, full-range, 1 MiB-crossing and PC-98 windows.
    // ------------------------------------------------------------------
    function automatic logic ref_in_window(input logic [31:0] addr,
                                           input logic [31:0] base,
                                           input logic [31:0] top);
        ref_in_window = (addr >= base) && (addr <= top);
    endfunction

    function automatic logic ref_window_match(input logic [31:0] addr_raw,
                                              input logic [31:0] addr_post,
                                              input logic [31:0] base,
                                              input logic [31:0] top);
        if (base[31:20] == top[31:20])
            ref_window_match = (addr_raw[19:0] >= base[19:0]) &&
                               (addr_raw[19:0] <= top[19:0]) &&
                               (addr_post[31:20] == base[31:20]);
        else
            ref_window_match = ref_in_window(addr_post, base, top);
    endfunction

    function automatic logic ref_page_in_window(input logic [19:0] pfn,
                                                input logic [31:0] base,
                                                input logic [31:0] top);
        ref_page_in_window = ref_in_window({pfn, 12'h000}, base, top);
    endfunction

    // Count mismatches for one address across every predicate.
    function automatic integer check_one_addr(input logic [31:0] addr,
                                              input logic [31:0] base,
                                              input logic [31:0] top);
        integer bad;
        bad = 0;
        if (z486_addr_in_window(addr, base, top) !== ref_in_window(addr, base, top))
            bad++;
        if (z486_page_in_window(addr[31:12], base, top) !==
            ref_page_in_window(addr[31:12], base, top))
            bad++;
        // A20 split view: raw low bits against the segment on the masked address.
        if (z486_window_match(addr, addr, base, top) !==
            ref_window_match(addr, addr, base, top))
            bad++;
        if (z486_window_match(addr, addr & 32'hffef_ffff, base, top) !==
            ref_window_match(addr, addr & 32'hffef_ffff, base, top))
            bad++;
        if (z486_window_match(addr, addr & 32'h000f_ffff, base, top) !==
            ref_window_match(addr, addr & 32'h000f_ffff, base, top))
            bad++;
        return bad;
    endfunction

    task automatic check_window_predicates(input string name,
                                           input logic [31:0] base,
                                           input logic [31:0] top);
        integer mism;
        logic [31:0] a;
        logic [31:0] seed;
        mism = 0;
        seed = 32'h1234_5678;
        // Both window edges and +-1, plus the address-space corners.
        mism += check_one_addr(base - 32'd1, base, top);
        mism += check_one_addr(base, base, top);
        mism += check_one_addr(base + 32'd1, base, top);
        mism += check_one_addr(top - 32'd1, base, top);
        mism += check_one_addr(top, base, top);
        mism += check_one_addr(top + 32'd1, base, top);
        mism += check_one_addr(32'h0000_0000, base, top);
        mism += check_one_addr(32'hffff_ffff, base, top);
        mism += check_one_addr(32'h8000_0000, base, top);
        for (int i = 0; i < 256; i++) begin
            seed = seed * 32'd1664525 + 32'd1013904223;
            a = seed;
            mism += check_one_addr(a, base, top);
            mism += check_one_addr(a & 32'h000f_ffff, base, top);
            mism += check_one_addr(a & 32'h07ff_ffff, base, top);
        end
        check_word(name, mism[31:0], 32'd0);
    endtask

    // Runtime-bound sweep: `base`/`top` come from an LCG and from register-free
    // expressions, so nothing can be constant-folded and the non-constant path
    // (trailing-bit scan + shift, or the aligned masked-equality branch) is the
    // one that actually runs. Pins bit-exactness for non-constant bounds.
    task automatic check_runtime_predicates;
        integer mism;
        logic [31:0] b, t, a, seed;
        mism = 0;
        seed = 32'hc0ff_ee01;
        for (int i = 0; i < 512; i++) begin
            seed = seed * 32'd1664525 + 32'd1013904223;
            b = seed;
            seed = seed * 32'd1664525 + 32'd1013904223;
            t = seed;
            // Shapes that stress the reduction for dynamic bounds too.
            case (i % 8)
              0: t = b + 32'h0000_ffff;                  // unaligned unless b is aligned
              1: t = (b & ~32'h000f_ffff) | 32'h000f_ffff; // 1 MiB-aligned power of two
              2: t = b;                                  // single address
              3: t = 32'hffff_ffff;                      // full range from b
              4: t = b - 32'd1;                          // reversed (empty)
              5: t = b | 32'h0000_0fff;                  // small span
              6: t = b + 32'h0010_0000;                  // 1 MiB span
              default: t = b + 32'h0000_00ff;            // tiny span
            endcase
            for (int j = 0; j < 5; j++) begin
                seed = seed * 32'd1664525 + 32'd1013904223;
                a = (j == 0) ? b : (j == 1) ? t :
                    (j == 2) ? (b - 32'd1) : (j == 3) ? (t + 32'd1) : seed;
                if (z486_addr_in_window(a, b, t) !== ref_in_window(a, b, t))
                    mism++;
                if (z486_page_in_window(a[31:12], b, t) !==
                    ref_page_in_window(a[31:12], b, t))
                    mism++;
                if (z486_window_match(a, a, b, t) !==
                    ref_window_match(a, a, b, t))
                    mism++;
                if (z486_window_match(a, a & 32'hffef_ffff, b, t) !==
                    ref_window_match(a, a & 32'hffef_ffff, b, t))
                    mism++;
                if (z486_window_match(a, a & 32'h000f_ffff, b, t) !==
                    ref_window_match(a, a & 32'h000f_ffff, b, t))
                    mism++;
            end
        end
        check_word("runtime-bound predicate equivalence (dynamic base/top)",
                   mism[31:0], 32'd0);
    endtask

    // VGA window enabled on the raw address (VGA_PRE_WRAP=1).
    function automatic z486_cache_class_t def_class(input logic [31:0] addr);
        def_class = z486_classify_phys(
            addr, addr, addr,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b0, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b0, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'h0008_0000, 32'h0009_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'hffff_ffff);
    endfunction

    // Default build: no template window (the classifier is inert).
    function automatic z486_cache_class_t def_inert_class(input logic [31:0] addr);
        def_inert_class = z486_classify_phys(
            addr, addr, addr,
            1'b0, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b0, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b0, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'h0008_0000, 32'h0009_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'hffff_ffff);
    endfunction

    // VGA window enabled on the A20-masked physical (VGA_PRE_WRAP=0).
    function automatic z486_cache_class_t vga_postwrap_class(input logic [31:0] raw,
                                                             input logic [31:0] post);
        vga_postwrap_class = z486_classify_phys(
            raw, post, post,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b0, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b0, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'h0008_0000, 32'h0009_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'hffff_ffff);
    endfunction

    // PC-98 preset: A20 off clears bit 20 only (the Xe10's gate drives A20M#);
    // A0000-FFFFF and aliases non-cacheable. The value is the preset's own.
    localparam [31:0] PC98_A20_MASK_OFF = `Z486_PC98_A20_MASK_OFF;
    // No-allocate bound straight from the preset (the 128 MiB L1 tag reach).
    localparam [31:0] PC98_RAM_TOP      = `Z486_PC98_NO_ALLOC_BOUND;
    // A platform override: 96 MiB of RAM, everything above it no-allocate.
    localparam [31:0] PC98_RAM_TOP_96M  = 32'h0600_0000;

    function automatic z486_cache_class_t pc98_class(input logic [31:0] addr,
                                                     input logic win0_unmapped);
        pc98_class = z486_classify_phys(
            addr, addr, addr,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b1, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b1 && win0_unmapped, Z486_CACHE_NO_ALLOC,
            32'h0008_0000, 32'h0009_ffff,
            1'b1, Z486_CACHE_NO_ALLOC, PC98_RAM_TOP);
    endfunction

    // PC-98 windows with the bound overridden to a 96 MiB RAM top.
    function automatic z486_cache_class_t pc98_96m_class(input logic [31:0] addr);
        pc98_96m_class = z486_classify_phys(
            addr, addr, addr,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b1, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'h0008_0000, 32'h0009_ffff,
            1'b1, Z486_CACHE_NO_ALLOC, PC98_RAM_TOP_96M);
    endfunction

    // Same windows without the no-allocate bound (alias class visible).
    function automatic z486_cache_class_t pc98_nobound_class(input logic [31:0] addr);
        pc98_nobound_class = z486_classify_phys(
            addr, addr, addr,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000b_ffff,
            1'b1, Z486_CACHE_DIRECT, 32'h000a_0000, 32'h000f_ffff,
            1'b1, Z486_CACHE_DIRECT,
            32'h00f0_0000, 32'h00ff_ffff,
            32'hfff0_0000, 32'hfff7_ffff,
            32'hffff_8000, 32'hffff_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, 32'h0008_0000, 32'h0009_ffff,
            1'b0, Z486_CACHE_NO_ALLOC, PC98_RAM_TOP);
    endfunction

    initial begin
        $display("--- window predicate ---");
        check_bit("addr A0000 in VGA", z486_addr_in_window(32'h000a_0000, 32'h000a_0000, 32'h000b_ffff), 1'b1);
        check_bit("addr BFFFF in VGA", z486_addr_in_window(32'h000b_ffff, 32'h000a_0000, 32'h000b_ffff), 1'b1);
        check_bit("addr 9FFFF not in VGA", z486_addr_in_window(32'h0009_ffff, 32'h000a_0000, 32'h000b_ffff), 1'b0);
        check_bit("addr C0000 not in VGA", z486_addr_in_window(32'h000c_0000, 32'h000a_0000, 32'h000b_ffff), 1'b0);

        $display("--- A20 split window match ---");
        // Aperture A0000-FFFFF with the demand path's bit-20-clear mask.
        check_bit("split 0x001A0000/0x000A0000 aperture",
                  z486_window_match(32'h001a_0000, 32'h000a_0000, 32'h000a_0000, 32'h000f_ffff), 1'b1);
        check_bit("split 0x0019FFFF/0x0009FFFF not aperture",
                  z486_window_match(32'h0019_ffff, 32'h0009_ffff, 32'h000a_0000, 32'h000f_ffff), 1'b0);
        check_bit("split 0x00F00000/0x00F00000 alias0",
                  z486_window_match(32'h00f0_0000, 32'h00f0_0000, 32'h00f0_0000, 32'h00ff_ffff), 1'b1);
        check_bit("split 0xFFFF8000/0xFFFF8000 alias2",
                  z486_window_match(32'hffff_8000, 32'hffff_8000, 32'hffff_8000, 32'hffff_ffff), 1'b1);

        $display("--- page predicate (TLB stored class) ---");
        check_bit("pfn A0 in VGA", z486_page_in_window(20'h000a0, 32'h000a_0000, 32'h000b_ffff), 1'b1);
        check_bit("pfn BF in VGA", z486_page_in_window(20'h000bf, 32'h000a_0000, 32'h000b_ffff), 1'b1);
        check_bit("pfn 9F not in VGA", z486_page_in_window(20'h0009f, 32'h000a_0000, 32'h000b_ffff), 1'b0);
        check_bit("pfn C0 not in VGA", z486_page_in_window(20'h000c0, 32'h000a_0000, 32'h000b_ffff), 1'b0);
        // pfn[19:5]==15'h5 equivalence, exhaustive over the low 12 bits.
        begin
            logic [19:0] p;
            integer mism = 0;
            for (int i = 0; i < 4096; i++) begin
                p = i[19:0];
                if (z486_page_in_window(p, 32'h000a_0000, 32'h000b_ffff) !==
                    (p[19:5] == 15'h5))
                    mism++;
            end
            check_word("pfn[19:5]==5 exhaustive (low 12 bits)", mism, 0);
        end

        $display("--- PC/AT default preset classification ---");
        check_class("default 0x00000000 cacheable", def_class(32'h0000_0000), Z486_CACHE_CACHEABLE);
        check_class("default 0x0009FFFF cacheable", def_class(32'h0009_ffff), Z486_CACHE_CACHEABLE);
        check_class("default 0x000A0000 direct",    def_class(32'h000a_0000), Z486_CACHE_DIRECT);
        check_class("default 0x000BFFFF direct",    def_class(32'h000b_ffff), Z486_CACHE_DIRECT);
        check_class("default 0x000C0000 cacheable", def_class(32'h000c_0000), Z486_CACHE_CACHEABLE);
        check_class("default 0x000FFFFF cacheable", def_class(32'h000f_ffff), Z486_CACHE_CACHEABLE);
        check_class("default 0x00100000 cacheable", def_class(32'h0010_0000), Z486_CACHE_CACHEABLE);
        check_class("default 0x00F00000 cacheable", def_class(32'h00f0_0000), Z486_CACHE_CACHEABLE);
        check_class("default 0xFFFF8000 cacheable", def_class(32'hffff_8000), Z486_CACHE_CACHEABLE);

        $display("--- default build: no template window (structurally inert) ---");
        check_class("inert 0x0009FFFF cacheable", def_inert_class(32'h0009_ffff), Z486_CACHE_CACHEABLE);
        check_class("inert 0x000A0000 cacheable", def_inert_class(32'h000a_0000), Z486_CACHE_CACHEABLE);
        check_class("inert 0x000BFFFF cacheable", def_inert_class(32'h000b_ffff), Z486_CACHE_CACHEABLE);
        check_class("inert 0x000F0000 cacheable", def_inert_class(32'h000f_0000), Z486_CACHE_CACHEABLE);
        check_class("inert 0x00F00000 cacheable", def_inert_class(32'h00f0_0000), Z486_CACHE_CACHEABLE);
        check_class("inert 0x00080000 cacheable", def_inert_class(32'h0008_0000), Z486_CACHE_CACHEABLE);
        check_class("inert 0xFFFFFFFF cacheable", def_inert_class(32'hffff_ffff), Z486_CACHE_CACHEABLE);

        $display("--- VGA window on the post-wrap physical (VGA_PRE_WRAP=0) ---");
        // PC-98 A20 off: 0x001A0000 masks to the 0x000A0000 window.
        check_class("post-wrap 0x1A0000/0x0A0000 direct",
                    vga_postwrap_class(32'h001a_0000, 32'h000a_0000), Z486_CACHE_DIRECT);
        check_class("post-wrap 0x0A0000/0x0A0000 direct",
                    vga_postwrap_class(32'h000a_0000, 32'h000a_0000), Z486_CACHE_DIRECT);
        check_class("post-wrap 0x0C0000/0x0C0000 cacheable",
                    vga_postwrap_class(32'h000c_0000, 32'h000c_0000), Z486_CACHE_CACHEABLE);
        check_class("post-wrap 0x1BFFFF/0x0BFFFF direct",
                    vga_postwrap_class(32'h001b_ffff, 32'h000b_ffff), Z486_CACHE_DIRECT);

        $display("--- PC-98 preset classification ---");
        check_class("pc98 0x0009FFFF cacheable",   pc98_class(32'h0009_ffff, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 0x000A0000 direct",      pc98_class(32'h000a_0000, 1'b0), Z486_CACHE_DIRECT);
        check_class("pc98 0x000C0000 direct",      pc98_class(32'h000c_0000, 1'b0), Z486_CACHE_DIRECT);
        check_class("pc98 0x000FFFFF direct",      pc98_class(32'h000f_ffff, 1'b0), Z486_CACHE_DIRECT);
        check_class("pc98 0x00F00000 direct",      pc98_class(32'h00f0_0000, 1'b0), Z486_CACHE_DIRECT);
        check_class("pc98 0x00FFFFFF direct",      pc98_class(32'h00ff_ffff, 1'b0), Z486_CACHE_DIRECT);
        // Above the bound, NO_ALLOC shadows the alias windows.
        check_class("pc98 0xFFF00000 no-alloc",    pc98_class(32'hfff0_0000, 1'b0), Z486_CACHE_NO_ALLOC);
        check_class("pc98 0xFFF7FFFF no-alloc",    pc98_class(32'hfff7_ffff, 1'b0), Z486_CACHE_NO_ALLOC);
        check_class("pc98 0xFFFF8000 no-alloc",    pc98_class(32'hffff_8000, 1'b0), Z486_CACHE_NO_ALLOC);
        check_class("pc98 0xFFFFFFFF no-alloc",    pc98_class(32'hffff_ffff, 1'b0), Z486_CACHE_NO_ALLOC);
        // Without the bound the alias windows are DIRECT (the device class).
        check_class("pc98-nobound 0xFFF00000 direct", pc98_nobound_class(32'hfff0_0000), Z486_CACHE_DIRECT);
        check_class("pc98-nobound 0xFFF7FFFF direct", pc98_nobound_class(32'hfff7_ffff), Z486_CACHE_DIRECT);
        check_class("pc98-nobound 0xFFFF8000 direct", pc98_nobound_class(32'hffff_8000), Z486_CACHE_DIRECT);
        check_class("pc98-nobound 0xFFFFFFFF direct", pc98_nobound_class(32'hffff_ffff), Z486_CACHE_DIRECT);
        // Extended RAM above the 15-16 MiB hole stays cacheable up to the
        // 128 MiB L1 tag reach; the bound starts exactly there.
        check_word("pc98 preset bound is the L1 tag reach",
                   PC98_RAM_TOP, 32'h0800_0000);
        check_class("pc98 0x00FFFFFF direct",      pc98_class(32'h00ff_ffff, 1'b0), Z486_CACHE_DIRECT);
        check_class("pc98 0x01000000 cacheable",   pc98_class(32'h0100_0000, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 0x02000000 cacheable",   pc98_class(32'h0200_0000, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 0x05FFFFFF cacheable",   pc98_class(32'h05ff_ffff, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 0x07FFFFFF cacheable",   pc98_class(32'h07ff_ffff, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 0x08000000 no-alloc",    pc98_class(32'h0800_0000, 1'b0), Z486_CACHE_NO_ALLOC);
        check_class("pc98 0x10000000 no-alloc",    pc98_class(32'h1000_0000, 1'b0), Z486_CACHE_NO_ALLOC);
        // 96 MiB RAM-top override.
        check_class("pc98-96M 0x01000000 cacheable", pc98_96m_class(32'h0100_0000), Z486_CACHE_CACHEABLE);
        check_class("pc98-96M 0x05FFFFFF cacheable", pc98_96m_class(32'h05ff_ffff), Z486_CACHE_CACHEABLE);
        check_class("pc98-96M 0x06000000 no-alloc",  pc98_96m_class(32'h0600_0000), Z486_CACHE_NO_ALLOC);
        check_class("pc98-96M 0x00F00000 direct",    pc98_96m_class(32'h00f0_0000), Z486_CACHE_DIRECT);
        check_class("pc98-96M 0xFFFF8000 no-alloc",  pc98_96m_class(32'hffff_8000), Z486_CACHE_NO_ALLOC);
        // window-0 overlay only classifies when the runtime verdict is asserted
        check_class("pc98 win0 0x00080000 mapped cacheable",
                    pc98_class(32'h0008_0000, 1'b0), Z486_CACHE_CACHEABLE);
        check_class("pc98 win0 0x00080000 unmapped no-alloc",
                    pc98_class(32'h0008_0000, 1'b1), Z486_CACHE_NO_ALLOC);
        check_class("pc98 win0 0x0009FFFF unmapped no-alloc",
                    pc98_class(32'h0009_ffff, 1'b1), Z486_CACHE_NO_ALLOC);
        check_class("pc98 win0 0x000A0000 unmapped direct (aperture wins)",
                    pc98_class(32'h000a_0000, 1'b1), Z486_CACHE_DIRECT);

        $display("--- reduced-predicate equivalence (vs magnitude) ---");
        check_window_predicates("eq VGA A0000-BFFFF",      32'h000a_0000, 32'h000b_ffff);
        check_window_predicates("eq aperture A0000-FFFFF", 32'h000a_0000, 32'h000f_ffff);
        check_window_predicates("eq alias0 F00000-FFFFFF", 32'h00f0_0000, 32'h00ff_ffff);
        check_window_predicates("eq alias1 FFF00000-FFF7FFFF", 32'hfff0_0000, 32'hfff7_ffff);
        check_window_predicates("eq alias2 FFFF8000-FFFFFFFF", 32'hffff_8000, 32'hffff_ffff);
        check_window_predicates("eq win0 80000-9FFFF",      32'h0008_0000, 32'h0009_ffff);
        check_window_predicates("eq ram 10000000-1FFFFFFF", 32'h1000_0000, 32'h1fff_ffff);
        check_window_predicates("eq 1MiB cross FFFFF-100000",32'h000f_ffff, 32'h0010_0000);
        check_window_predicates("eq cross MSB 7FFFFFFF-80000001", 32'h7fff_ffff, 32'h8000_0001);
        check_window_predicates("eq unaligned 12345-9ABCD", 32'h0001_2345, 32'h0009_abcd);
        check_window_predicates("eq small 8-10",           32'h0000_0008, 32'h0000_0010);
        check_window_predicates("eq single FFFFFFFF",      32'hffff_ffff, 32'hffff_ffff);
        check_window_predicates("eq single 00000000",      32'h0000_0000, 32'h0000_0000);
        check_window_predicates("eq single 08000000",      32'h0800_0000, 32'h0800_0000);
        check_window_predicates("eq full 00000000-FFFFFFFF", 32'h0000_0000, 32'hffff_ffff);
        check_window_predicates("eq low segment 0-FFFF",   32'h0000_0000, 32'h0000_ffff);
        check_window_predicates("eq empty 0100-0010",      32'h0000_0100, 32'h0000_0010);

        $display("--- runtime-bound predicate equivalence ---");
        check_runtime_predicates;

        // The default-window strength reduction in z486_page_in_window must
        // agree with the general page compare for every pfn.
        $display("--- default VGA page predicate vs pfn[19:5] == 5 ---");
        begin : check_default_page_window
            integer mism;
            mism = 0;
            for (int p = 0; p < (1 << 20); p++) begin
                if (z486_page_in_window(p[19:0], 32'h000a_0000, 32'h000b_ffff) !==
                    (p[19:5] == 15'h5))
                    mism++;
            end
            if (mism != 0) begin
                $display("FAIL default VGA page predicate: %0d / %0d pfn disagree",
                         mism, 1 << 20);
                errors++;
            end else begin
                $display("ok   default VGA page predicate == pfn[19:5] == 5 for all %0d pfn",
                         1 << 20);
            end
        end

        $display("--- A20 policy masks ---");
        check_word("default A20 off bit20 clear",
                   (32'h001a_0000 & ~32'h0010_0000), 32'h000a_0000);
        check_word("default A20 off keeps A0000",
                   (32'h000a_0000 & ~32'h0010_0000), 32'h000a_0000);
        // The reset fetch with A20 masked lands on 0xFFEFFFF0, so a PC-98
        // platform decodes its BIOS at 0xFFEE8000-0xFFEFFFFF as well as at
        // 0xFFFE8000-0xFFFFFFFF (MAME pc9821.cpp maps the IPL bank at both).
        check_word("pc98 A20 off clears bit 20 of the reset vector",
                   (32'hffff_fff0 & PC98_A20_MASK_OFF), 32'hffef_fff0);
        check_word("pc98 A20 off 1A0000 -> 0A0000",
                   (32'h001a_0000 & PC98_A20_MASK_OFF), 32'h000a_0000);
        check_word("pc98 A20 off keeps bit 21 (2A0000)",
                   (32'h002a_0000 & PC98_A20_MASK_OFF), 32'h002a_0000);

        if (errors == 0) begin
            $display("MEMMAP TEMPLATE UNIT TEST PASS");
            $finish;
        end else begin
            $display("MEMMAP TEMPLATE UNIT TEST FAIL: %0d errors", errors);
            $fatal(1);
        end
    end
endmodule
