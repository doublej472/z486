#!/usr/bin/env python3
"""Generate a synthesis harness that wraps gpr_write_merge for Quartus.

The merge is purely combinational and has ~1.5k port bits, so it cannot be a
Quartus top-level entity (not enough device pins) and TimeQuest has no clock to
analyse.  This harness makes it an internal block with three external pins:

  * every DUT input is driven from a registered counter XORed with a per-port
    prime, so no input is constant and no lane enable is tied;
  * every DUT output is captured in a register and XOR-folded into `obs`, so the
    fitter cannot prune any part of the cone;
  * the measured path is counter -> merge -> output register, which is the real
    register-to-register path of the forwarding views.

Quartus 17's Verilog frontend rejects a part-select applied to an expression
result, so each port gets a named pattern wire first.

Generated from each revision's own port list so both sides of a before/after
comparison get mechanically identical treatment.
"""
import re
import sys


def ports(path):
    src = open(path).read()
    hdr = src[src.index('module gpr_write_merge'):]
    hdr = hdr[hdr.index('(') + 1:hdr.index('\n);')]
    hdr = re.sub(r'//[^\n]*', '', hdr)  # trailing comments hide the next port
    out = []
    for decl in re.split(r',\s*\n', hdr):
        m = re.match(r'\s*(input|output)\s+logic\s*(?:\[(\d+):(\d+)\])?\s*([a-z_0-9]+)', decl)
        if m:
            d, hi, lo, n = m.groups()
            out.append((d, (abs(int(hi) - int(lo)) + 1) if hi else 1, n))
    return out


def gen(dut, out_path):
    P = ports(dut)
    ins = [p for p in P if p[0] == 'input']
    outs = [p for p in P if p[0] == 'output']

    L = ['module merge_synth (input logic clk, input logic rst, output logic [31:0] obs);',
         "    logic [31:0] cnt;",
         "    always_ff @(posedge clk) begin",
         "        if (rst) cnt <= 32'h1234_5678;",
         "        else     cnt <= cnt + 32'd1;",
         "    end", ""]

    # Declare every DUT-connected net explicitly first: an assign to an
    # undeclared name creates an implicit one-bit net and silently truncates.
    for _, w, n in P:
        L.append("    logic [%d:0] %s;" % (w - 1, n) if w > 1 else "    logic %s;" % n)
    L.append("")

    # One 32-bit pattern per input port, then a plain part-select from it.
    for i, (_, w, n) in enumerate(ins):
        prime = 2654435761 + i * 40503
        L.append("    logic [31:0] pat_%s;" % n)
        L.append("    assign pat_%s = cnt ^ 32'h%08X;" % (n, prime & 0xFFFFFFFF))
        if w <= 32:
            L.append("    assign %s = pat_%s[%d:0];" % (n, n, w - 1) if w > 1
                     else "    assign %s = pat_%s[0];" % (n, n))
        else:
            reps = (w + 31) // 32
            L.append("    logic [%d:0] cat_%s;" % (reps * 32 - 1, n))
            L.append("    assign cat_%s = {%d{pat_%s}};" % (n, reps, n))
            L.append("    assign %s = cat_%s[%d:0];" % (n, n, w - 1))
    L.append("")

    for _, w, n in outs:
        L.append("    logic [%d:0] q_%s;" % (w - 1, n) if w > 1 else "    logic q_%s;" % n)
    L.append("")
    L.append("    gpr_write_merge dut (")
    L.append("        " + ",\n        ".join(".%s(%s)" % (n, n) for _, _, n in P))
    L.append("    );")
    L.append("")
    L.append("    always_ff @(posedge clk) begin")
    for _, _, n in outs:
        L.append("        q_%s <= %s;" % (n, n))
    L.append("    end")
    L.append("")
    L.append("    always_comb begin : observe")
    L.append("        obs = 32'd0;")
    for _, w, n in outs:
        L.append("        for (int i = 0; i < %d; i++) obs[i %% 32] ^= q_%s[i];" % (w, n))
    L.append("    end")
    L.append("endmodule")
    open(out_path, 'w').write('\n'.join(L) + '\n')
    return len(ins), len(outs), sum(w for _, w, _ in P)


if __name__ == '__main__':
    n_in, n_out, bits = gen(sys.argv[1], sys.argv[2])
    print('%s: %d inputs, %d outputs, %d port bits wrapped' % (sys.argv[2], n_in, n_out, bits))
