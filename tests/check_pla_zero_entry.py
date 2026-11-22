#!/usr/bin/env python3
"""No reachable PLA entry point is microcode address 000 (the reset routine).

decoder.sv dispatches an instruction through two committed ROM images:

  pla_entry_rom.hex    first level, 1024 x 64 bits at {opcode, rep, 0F}, four
                       16-bit lanes selected by {data32, pe_enable};
  pla_group_entry.hex  second level, 1024 x 16 bits at {group, ModR/M.reg,
                       memory}, used when the opcode has a ModR/M byte and the
                       first-level word is a group row (entry[11:6] == 0,
                       row = entry[5:0]).

Any reachable word whose entry[11:0] is 000 sends that instruction to the
reset microcode (ESC DB /6 m did, from a missing row in the 80386 dump).  This
walks every opcode of both maps (one-byte and 0F), rep, data32 x PE, and for
group opcodes every ModR/M.reg in register and memory form, the way the
decoder forms its addresses (decoder.sv entry_rom_addr / entry_rom_sel and
grom_addr / entry_grom), with has_modrm from pla_control_opcode_lookup.  It is
conservative: an opcode the decoder overrides after the PLA (BSWAP, XADD,
CMPXCHG, INVD, LOADALL, MOV TRn, an invalid LOCK) is still required to have a
nonzero PLA word.

    check_pla_zero_entry.py              check the committed images
    check_pla_zero_entry.py --selftest   plant zero words and require a FAIL
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def words(path: Path) -> list[int]:
    return [int(w, 16) for line in path.read_text().splitlines()
            for w in line.split('//', 1)[0].split()]


def control_patterns(path: Path) -> list[tuple[str, int]]:
    pats = []
    in_func = False
    for line in path.read_text().splitlines():
        if 'function automatic' in line and 'pla_control_opcode_lookup' in line:
            in_func = True
        if not in_func:
            continue
        m = re.search(r"9'b([01?_]+)\s*:\s*pla_control_opcode_lookup\s*=\s*\d+'b([01]+)\s*;",
                      line)
        if m:
            pats.append((m.group(1).replace('_', ''), int(m.group(2), 2)))
        if 'endfunction' in line:
            break
    if not pats:
        sys.exit(f'no pla_control_opcode_lookup patterns in {path}')
    return pats


def casez(pats, addr: int, width: int) -> int:
    s = format(addr, f'0{width}b')
    for p, v in pats:
        if all(pc in ('?', sc) for pc, sc in zip(p, s)):
            return v
    return 0


def has_modrm_table(ctl_pats) -> list[bool]:
    """has_modrm per {0F, opcode}, as decoder.sv: ctl_bits[2] & ~ctl_bits[0]."""
    out = []
    for addr in range(512):
        ctl = casez(ctl_pats, addr, 9)
        out.append(bool((ctl >> 2) & 1) and not (ctl & 1))
    return out


def zero_entries(first: list[int], group: list[int], modrm: list[bool]) -> list[str]:
    if len(first) != 1024 or len(group) != 1024:
        return [f'image size: first {len(first)}, group {len(group)} (want 1024 each)']
    found = []
    for has_0f in (0, 1):
        for opcode in range(256):
            name = f"{'0F ' if has_0f else ''}{opcode:02X}"
            for rep in (0, 1):
                word = first[(opcode << 2) | (rep << 1) | has_0f]
                for data32 in (0, 1):
                    for pe in (0, 1):
                        entry = (word >> (((data32 << 1) | pe) * 16)) & 0xFFFF
                        where = f'{name} rep={rep} data32={data32} pe={pe}'
                        if modrm[(has_0f << 8) | opcode] and ((entry >> 6) & 0x3F) == 0:
                            row = entry & 0x3F
                            for reg in range(8):
                                for memory in (0, 1):
                                    addr = (row << 4) | (reg << 1) | memory
                                    if (group[addr] & 0xFFF) == 0:
                                        found.append(
                                            f'{where} /{reg} {"m" if memory else "r"}: '
                                            f'group ROM word {addr:03X} (row {row:02X}) = 000')
                        elif (entry & 0xFFF) == 0:
                            found.append(f'{where}: first-level word = 000')
    # One line per distinct ROM word, with the first instruction reaching it.
    seen, out = set(), []
    for f in found:
        key = f.split(': ', 1)[1]
        if key not in seen:
            seen.add(key)
            out.append(f)
    return out


def check(first, group, modrm, label: str) -> bool:
    bad = zero_entries(first, group, modrm)
    for b in bad:
        print(f'  {label}: {b}')
    return not bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n', 1)[0])
    ap.add_argument('--selftest', action='store_true',
                    help='plant zero words in copies of the images; each must FAIL')
    args = ap.parse_args()

    first = words(ROOT / 'pla_entry_rom.hex')
    group = words(ROOT / 'pla_group_entry.hex')
    modrm = has_modrm_table(control_patterns(ROOT / 'pla_control.svh'))

    if not args.selftest:
        if check(first, group, modrm, 'PLA ZERO ENTRY'):
            print('PLA ZERO ENTRY PASS: no reachable first-level or group entry is 000 '
                  '(one-byte and 0F maps, rep, data32 x PE, every ModR/M.reg, r and m)')
            return 0
        print('PLA ZERO ENTRY FAIL: reachable entry point 000 (the reset microcode)')
        return 1

    if not check(first, group, modrm, 'baseline'):
        print('PLA ZERO ENTRY SELFTEST FAIL: the committed images do not pass')
        return 1
    mutants = []
    # 1. The B1 word: ESC DB /6 m, group 37h reg 6 memory, back to 000.
    g = list(group)
    g[(0x37 << 4) | (6 << 1) | 1] = 0
    mutants.append(('group 37h /6 m = 000', first, g))
    # 2. A first-level word of an opcode without ModR/M: NOP (90h), one lane.
    f = list(first)
    f[0x90 << 2] &= ~(0xFFF << (3 * 16))     # data32=1 pe=1 lane
    mutants.append(('first-level 90h data32=1 pe=1 = 000', f, group))
    # 3. A register-form group word in the 0F map: 0F 01 /0 r (group 21h).
    g = list(group)
    g[(0x21 << 4) | (0 << 1) | 0] = 0
    mutants.append(('group 21h /0 r = 000', first, g))
    bad = 0
    for label, f, g in mutants:
        caught = bool(zero_entries(f, g, modrm))
        print(f"  mutant {label}: {'caught' if caught else 'MISSED'}")
        bad += not caught
    if bad:
        print(f'PLA ZERO ENTRY SELFTEST FAIL: {bad} planted mutant(s) missed')
        return 1
    print(f'PLA ZERO ENTRY SELFTEST PASS: {len(mutants)}/{len(mutants)} planted mutants caught')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
