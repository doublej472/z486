#!/usr/bin/env python3
"""Dead-column scan of the z486 ROM images.

Quartus constant-folds a ROM column that is 0 (or 1) across every word: the
decoder entry ROM was narrowed from its declared 64 bits to 56 that way.  A
column that is constant AND still consumed by the RTL is therefore a missed
synthesis/area opportunity, while a constant column outside the consumed
slice is already free.

Checked here:
  ucode.hex           all 40 bits are consumed by ucode_rom.sv (37-bit native
                      word + 3-bit D2 early kind), so no column may be
                      constant.
  pla_entry_rom.hex   64 bits = 4 x 16-bit {data32,pe_enable} slices;
                      decoder.sv consumes bits [13:0] of the selected slice,
                      so a constant column is only allowed at [15:14].
  pla_group_entry.hex 16 bits; decoder.sv consumes bits [13:0], so a constant
                      column is only allowed at [15:14].

Usage: check_rom_columns.py <rtl-dir>
"""

import sys
from pathlib import Path

# file -> set of bit indices that the reader does not consume
ROMS = {
    "ucode.hex": None,              # None: every column is consumed
    "pla_entry_rom.hex": {b for f in range(4) for b in (16 * f + 14, 16 * f + 15)},
    "pla_group_entry.hex": {14, 15},
}


def scan(path):
    """Return (width, sorted list of (bit, value) that are constant)."""
    lines = [ln.strip() for ln in path.read_text().splitlines() if ln.strip()]
    if not lines:
        raise ValueError(f"{path}: no words")
    width = 4 * len(lines[0])
    if any(len(ln) * 4 != width for ln in lines):
        raise ValueError(f"{path}: inconsistent word widths")
    words = [int(ln, 16) for ln in lines]
    dead = []
    for bit in range(width):
        values = {(w >> bit) & 1 for w in words}
        if len(values) == 1:
            dead.append((bit, values.pop()))
    return width, dead


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1])
    failed = False
    for name, unused in ROMS.items():
        path = root / name
        width, dead = scan(path)
        live = [bit for bit, _ in dead if unused is None or bit not in unused]
        # Dead columns are scan findings; only columns the reader consumes are
        # a problem.
        print(f"{name}: {len(dead)} constant column(s) of {width}; "
              f"consumed-width can drop to {width - len(dead)}")
        if dead:
            print("  constant: " + ", ".join(f"bit {b}={v}" for b, v in dead))
        if live:
            print(f"  FAIL: consumed column(s) constant: {live}")
            failed = True
        else:
            print("  PASS: every consumed column varies")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
