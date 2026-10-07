#!/usr/bin/env python3
"""Build-time scan of ucode.hex for SHIFT/SHIFT1/SHIFT2/BITTST source pairings
that the pre-selected shifter operand muxes would decode differently from the
retired local muxes. Keep the tables in sync with the shift source class map
and old_shift_alu_mux in data_unit.sv. Usage: check_shift_ucode.py <ucode.hex>
"""

import sys

SHIFT_OPS = {0x10: "SHIFT", 0x02: "SHIFT1", 0x12: "SHIFT2", 0x11: "BITTST"}

# Raw source fields accepted for SHIFT words. SRC_SRCREG is only valid when the
# operand is captured into the shifter preread register (see below).
SHIFT_SOURCES = {
    0x1E: "SIGMA",    # class 1  -> sigma
    0x3D: "DSTREG",   # class 2  -> gpr_dst_shift_size
    0x3E: "SRCREG",   # class 3  -> captured only
    0x1F: "IMM",      # class 4  -> instr.immediate
    0x0B: "TMPB",     # class 5
    0x0C: "TMPC",     # class 6
    0x0D: "TMPD",     # class 7
    0x0E: "TMPE",     # class 8
    0x2D: "OPR_R",    # class 9
    0x14: "COUNTR",   # class 10
    0x3F: "NEG1",     # class 11 -> all ones
    0x38: "ZERO",     # class 0  -> zero
}

# ALU sources the retired local mux and the pre-selected mux agree on.
SHIFT_ALU_SOURCES = {
    0x38,  # ALUSRC_CONST_0
    0x0C,  # ALUSRC_TMPC
    0x0D,  # ALUSRC_TMPD
    0x0B,  # ALUSRC_TMPB
    0x3D,  # ALUSRC_DSTREG
    0x3E,  # ALUSRC_SRCREG
    0x01,  # ALUSRC_ECX
    0x09,  # ALUSRC_IMM
    0x3C,  # ALUSRC_BITS_V
    0x30,  # ALUSRC_CONST_1
    0x25,  # ALUSRC_CONST_3
    0x2C,  # ALUSRC_CONST_7
    0x22,  # ALUSRC_CONST_1FF
    0x17,  # ALUSRC_CONST_4000
    0x1B,  # ALUSRC_CONST_F0000
    0x36,  # ALUSRC_MASK16
    0x27,  # ALUSRC_CONST_FFFF0000
    0x26,  # ALUSRC_CONST_6 (local mux default 0; pre-selected mux special-case 0)
    0x3F,  # ALUSRC_ZERO
}


def scan(path):
    problems = []
    with open(path) as fh:
        for addr, line in enumerate(fh):
            line = line.strip()
            if not line:
                continue
            word = int(line, 16)
            aluop = (word >> 11) & 0x7F
            if aluop not in SHIFT_OPS:
                continue
            source = (word >> 18) & 0x3F
            alu_src = (word >> 31) & 0x3F
            captured = (aluop == 0x12) or (aluop == 0x10 and source == 0x3E)
            if source not in SHIFT_SOURCES or (source == 0x3E and not captured):
                problems.append(
                    "%03x: %s unrecognized source 0x%02x (captured=%d)"
                    % (addr, SHIFT_OPS[aluop], source, captured))
            if alu_src not in SHIFT_ALU_SOURCES:
                problems.append(
                    "%03x: %s unrecognized ALU source 0x%02x"
                    % (addr, SHIFT_OPS[aluop], alu_src))
    return problems


def main():
    if len(sys.argv) != 2:
        print("usage: check_shift_ucode.py <ucode.hex>", file=sys.stderr)
        return 2
    problems = scan(sys.argv[1])
    if problems:
        print("SHIFT source pairing scan FAILED (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("SHIFT source pairing scan passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
