#!/usr/bin/env python3
"""Annotated z486 microcode inspection.

The 40-bit ROM word is `ucode_optimize.py`'s documented layout, so this tool
imports that module for the field table and the generated-hex reader instead of
duplicating either.  Names come from the RTL's own `localparam` tables in
z486_pkg.sv, so a listing can never drift from the decoders.

Why this exists: questions like "can a younger instruction corrupt the fault
delivery's address?" are answered by *decoding the microcode*, not by reading
the datapath and guessing.  The AU's address mask depends on which microcode
words the delivery actually executes, and that is a ROM property.

Usage:
    ucode_disasm.py --list 8D2-8E3          annotated listing
    ucode_disasm.py --sensitive             words a given AU input can affect
    ucode_disasm.py --find-dest DES_CS      find words writing a destination
    ucode_disasm.py --find-aluop PTGEN      find words with an ALU/jump op
    ucode_disasm.py --delivery              summarise the fault-delivery path
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ucode_optimize as uo  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PKG = ROOT / "z486_pkg.sv"

# name -> (bus, dest) pairs that make the address unit mask an exec IND address
# to 16 bits from the *instruction's* `i.addr32`.  See ind_ctrl_predecode() in
# ucode_rom.sv: dest_class 3 (DESSEG) is {DES_ES, DES_OS, DES_SR}, and only
# INDOP_PLUS_ALU consults exec_addr32 for that class.
BUSOP_IND_PLUS_ALU = 0x26
DESSEG_DESTS = {0x5D, 0x5E, 0x60}


def load_localparams(path=PKG):
    """Reverse map value -> [names] from the RTL's localparam declarations."""
    names = {}
    pat = re.compile(
        r"\s*localparam\s+(?:\[\d+:\d+\]\s*)?(\w+)\s*=\s*"
        r"(?:(\d+)'([hbdo]))?([0-9A-Fa-fx_]+)\s*;")
    for line in path.read_text().splitlines():
        m = pat.match(line)
        if not m:
            continue
        _, _, base_char, digits = m.groups()
        try:
            if base_char == 'b':
                val = int(digits.replace('_', ''), 2)
            elif base_char == 'o':
                val = int(digits.replace('_', ''), 8)
            else:
                val = int(digits.replace('_', ''), 16)
        except ValueError:
            continue
        names.setdefault(val, []).append(m.group(1))
    return names


def read_hex(path):
    words = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        words.append(int(line, 16))
    return words


def name_of(names, value, prefix):
    for n in names.get(value, []):
        if n.startswith(prefix):
            return n
    return "-"


def write_field(w, field):
    return (w >> uo.FIELDS[field][0]) & ((1 << uo.FIELDS[field][1]) - 1)


def decode(words, addr, names):
    w = words[addr]
    return dict(
        addr=addr, word=w,
        bus=write_field(w, 'bus'), dst=write_field(w, 'dst'),
        op=write_field(w, 'op'), aluop=write_field(w, 'aluop'),
        src=write_field(w, 'src'), alusrc=write_field(w, 'alusrc'),
        bus_name=name_of(names, write_field(w, 'bus'), 'BUSOP'),
        dst_name=name_of(names, write_field(w, 'dst'), 'DEST'),
        aluop_name=name_of(names, write_field(w, 'aluop'), 'ALUJMP'),
        src_name=name_of(names, write_field(w, 'src'), 'SRC'),
    )


def fmt(d):
    return (f"{d['addr']:03X}  {d['bus']:02X} {d['bus_name']:<18} "
            f"{d['dst']:02X} {d['dst_name']:<15} {d['aluop']:02X} "
            f"{d['aluop_name']:<20} {d['src']:02X} {d['src_name']:<10} "
            f"{d['alusrc']:02X}")


def header():
    return ("addr  bus  name               dst name            aluop "
            "name                 src name       alusrc")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hex", default=str(ROOT / "ucode.hex"))
    ap.add_argument("--list", metavar="LO-HI",
                    help="annotated listing over an address range (hex)")
    ap.add_argument("--sensitive", action="store_true",
                    help="words whose exec IND mask depends on i.addr32 (DESSEG)")
    ap.add_argument("--find-dest", metavar="NAME", help="words writing a destination")
    ap.add_argument("--find-aluop", metavar="NAME", help="words with an ALU/jump op")
    ap.add_argument("--find-bus", metavar="NAME", help="words with a bus operation")
    ap.add_argument("--delivery", action="store_true",
                    help="summarise the fault-delivery path and its masks")
    args = ap.parse_args()

    names = load_localparams()
    words = read_hex(Path(args.hex))
    print(f"# {args.hex}: {len(words)} words, {uo.ROM_BITS}-bit\n", file=sys.stderr)

    if args.list:
        lo, hi = (int(x, 16) for x in args.list.split("-"))
        print(header())
        for a in range(lo, hi + 1):
            d = decode(words, a, names)
            mark = ""
            if d['bus'] == BUSOP_IND_PLUS_ALU and d['dst'] in DESSEG_DESTS:
                mark = "  <== i.addr32-sensitive"
            if d['dst'] == 0x21:
                mark += "  [writes CS]"
            print(fmt(d) + mark)
        return 0

    if args.sensitive:
        print("Words whose executed IND mask depends on i.addr32")
        print("(IND_PLUS_ALU with dest_class == DESSEG):\n")
        print(header())
        n = 0
        for a in range(len(words)):
            d = decode(words, a, names)
            if d['bus'] == BUSOP_IND_PLUS_ALU and d['dst'] in DESSEG_DESTS:
                print(fmt(d))
                n += 1
        print(f"\n{n} word(s)")
        return 0

    for opt, field, prefix in (("find_dest", 'dst', 'DEST'),
                               ("find_aluop", 'aluop', 'ALUJMP'),
                               ("find_bus", 'bus', 'BUSOP')):
        want = getattr(args, opt)
        if not want:
            continue
        hits = [a for a in range(len(words))
                if name_of(names, write_field(words[a], field), prefix) == want]
        print(f"Words with {field} == {want}: {len(hits)}\n")
        print(header())
        for a in hits:
            print(fmt(decode(words, a, names)))
        return 0

    if args.delivery:
        print("Fault/interrupt delivery path (decoded from ucode.hex).")
        print("The routine is entered at 0x8A0; the operand-size select decides")
        print("the width of the IDT gate address at 0x8D7.\n")
        print(header())
        for a in range(0x8A0, 0x8E4):
            d = decode(words, a, names)
            note = ""
            if d['aluop_name'] in ("ALUJMP_BITS16", "ALUJMP_BITS32"):
                note = f"  <= set {'16' if '16' in d['aluop_name'] else '32'}-bit mode"
            if d['dst'] == 0x59 and d['bus'] == 0x25:
                note = "  <= IDT gate read (DESCOD, masked by is_dword)"
            if d['dst'] == 0x5A and d['bus'] == BUSOP_IND_PLUS_ALU:
                note = "  <= frame push EA (DESSTK, masked by pe/ss_stack32)"
            if d['aluop_name'] == "ALUJMP_USTEP_FAULT_DONE":
                note = "  <= delivery completion"
            print(fmt(d) + note)
        return 0

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
