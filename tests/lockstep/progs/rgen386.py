#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 ZbuntowanyKamulec
"""Random real-mode 386/486 program generator for the 86Box lockstep test.

Usage: rgen386.py <out.bin> <seed> [nretire] [--pm]

--pg: --pm with paging ('RPG3' file): the testbench maps the first MB (directory 8D000,
table 8E000) with random not-present, read-only (CR0.WP set), aliased and PCD data
pages and not-present code pages; a #PF handler at FE00 sets P and W in the PTE,
INVLPGs and restarts.  MOV CR3 only reloads it, MOV CR0 keeps PE / PG / WP.

--pm: the same programs in 16-bit protected mode ('RPM3' file): the testbench builds a
GDT whose selectors equal the real-mode segment values (same bases, 64 KB limits) plus
test descriptors (TSTSEL), and an IDT of 16-bit interrupt gates to the IVT handlers;
a prologue at FF00 sets PE and jumps to the program.  Segment loads also use the test
selectors (faults are resumed as usual), system items keep PE and the tables.

16-bit real-mode code with random 66 / 67 / segment / LOCK / REP prefixes: the
8086 set plus the 186 / 386 / 486 user instructions, 32-bit operands and
32-bit (SIB) addressing.

Memory map
  0x00000  IVT (written by the testbench from the header)
  0x10000  CS=1000  code;  F000 fault handler, F100 resume table, F300 counter, FFF0 IRET stub
  0x30000  DS=3000, 0x40000 FS=4000, 0x50000 GS=5000, 0xB0000 ES=B000 (uncacheable)  random data
  0x70000  SS=7000  stack
Rules that keep a program alive under faults (#DE #BR #UD #SS #GP restart the
instruction, so the handler resumes at an instruction start from a table):
  * SP stays even (no word/dword register operand is SP, ESP's upper half is 0)
  * segment registers are only loaded with the data / stack segments above,
    nothing writes through CS, far transfers stay in CS
  * TF is never set
  * jump targets are always item starts; multi-instruction items are atomic

File: 'R386' u32 seed, nretire, gpr[8] (AX CX DX BX SP BP SI DI), u16 seg[6] (ES CS SS DS FS GS),
      u32 eip, eflags, u16 ivt[256] (handler offsets in CS), u8 code[65536]
"""
import random, struct, sys

CS, SS, DS, ES, FS, GS = 0x1000, 0x7000, 0x3000, 0xB000, 0x4000, 0x5000
DSEGS = [DS, ES, FS, GS, SS]
SEGPFX = [0x26, 0x36, 0x3E, 0x64, 0x65]      # never CS
H_FAULT, H_TABLE, H_CTR, H_IRET = 0xF000, 0xF100, 0xF300, 0xFFF0
FAULT_VECS = (0, 5, 6, 7, 12, 13)
PG = '--pg' in sys.argv
PM = ('--pm' in sys.argv) or PG
# protected mode: test selectors (see tb/tb_main.cpp: rpm_tables) and the GDT limit
TSTSEL = [0x0000, 0x0003, 0x0008, 0x0010, 0x0018, 0x0020, 0x0028, 0x0030, 0x0038, 0x0040, 0x004B, 0xFFF8]
H_PRO, H_GDTR, H_IDTR, H_EC1, H_EC2 = 0xFF00, 0xFFC0, 0xFFC8, 0xFFE0, 0xFFE8
H_PF, PD_ADDR, SEL_FLAT, SEL_PT = 0xFE00, 0x8D000, 0x50, 0x58      # paging (--pg)


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        # CR0.NW set by this program?  (then no locked RMW to memory: an i486 locked read
        # skips the cache, which holds stores that memory does not; 86Box has no cache)
        self.nw = False   # (lockstep vs z486: CR0.NW never set, z486 keeps NW write hits cache-only)
        self.items = []        # ('b', bytes) | ('br', opcode bytes, displacement size)
                               # | ('abs', prefix bytes, suffix bytes)  16-bit absolute target between them

    # ------------------------------------------------------------ helpers
    def rw(self):
        """a word / dword register that is not SP"""
        return self.r.choice([0, 1, 2, 3, 5, 6, 7])

    def imm(self, n):
        r = self.r
        if r.random() < 0.2:
            return list(r.choice([0, 1, 0xFF, 0x7F, 0x80]).to_bytes(1, 'little') * n)
        return [r.randrange(256) for _ in range(n)]

    def ea(self, reg, as32, mode='any', rmw=True):
        """modrm (+SIB, displacement) bytes and clean-up instructions for a 32-bit address.
        mode: 'any' | 'mem' | 'reg';  rmw: a register r/m is a word / dword register"""
        r = self.r
        pre = []
        if mode == 'reg' or (mode == 'any' and r.random() < 0.3):
            rm = self.rw() if rmw else r.randrange(8)
            return pre, [0xC0 | (reg << 3) | rm]
        mod = r.randrange(3)
        if not as32:
            rm = r.randrange(8)
            b = [(mod << 6) | (reg << 3) | rm]
            if mod == 1:
                b += self.imm(1)
            elif mod == 2 or (mod == 0 and rm == 6):
                b += self.imm(2)
            return pre, b
        used = []
        rm = r.randrange(8)
        b = [(mod << 6) | (reg << 3) | rm]
        base = rm
        if rm == 4:
            idx = r.randrange(8)
            scale = r.randrange(4) if idx != 4 else 0      # (no index with a scale is undefined)
            base = r.randrange(8)
            b.append((scale << 6) | (idx << 3) | base)
            if idx != 4:
                used.append(idx)
        nobase = (mod == 0 and base == 5)
        if not nobase:
            used.append(base)
        if mod == 1:
            b += self.imm(1)
        elif mod == 2 or nobase:
            b += [r.randrange(256), r.randrange(256), 0, 0] if r.random() < 0.9 else self.imm(4)
        # mostly make the registers of the address 16-bit clean, so it has a chance to be in range
        if r.random() < 0.75:
            for x in set(used):
                if x != 4:
                    pre += [0x66, 0x0F, 0xB7, 0xC0 | (x << 3) | x]      # movzx e?x, ?x
        return pre, b

    def emit(self, b):
        self.items.append(('b', bytes(b)))

    def ins(self, opc, reg=None, mode=None, w=True, regw=None, rmw=None, imm=None, seg=True,
            a66=True, a67=True, lock=False, os=None, as_=None, pre=None):
        """one instruction with random prefixes.
        opc: opcode bytes;  mode: None (no modrm) / 'any' / 'mem' / 'reg';  w: word-sized operation
        (66 applies);  regw / rmw: the reg / rm register operand is word-sized (default w);
        imm: None, 'b', 'w', 'z' (operand size), or a list of bytes"""
        r = self.r
        regw = w if regw is None else regw
        rmw = w if rmw is None else rmw
        os32 = (a66 and r.random() < 0.3) if os is None else os
        as32 = (a67 and mode is not None and r.random() < 0.12) if as_ is None else as_
        p = []
        if os32:
            p.append(0x66)
        if as32:
            p.append(0x67)
        b = list(opc)
        cl = list(pre or [])
        ismem = False
        if mode is not None:
            if reg is None:
                reg = self.rw() if regw else r.randrange(8)
            c, m = self.ea(reg, as32, mode, rmw)
            cl += c
            b += m
            ismem = (m[0] >> 6) != 3
        if ismem and seg and r.random() < 0.2:
            p.append(r.choice(SEGPFX))
        if lock and ismem and not self.nw and r.random() < 0.3:
            p.append(0xF0)
        if imm == 'b':
            b += self.imm(1)
        elif imm == 'w':
            b += self.imm(2)
        elif imm == 'z':
            b += self.imm(4 if os32 else 2)
        elif imm is not None:
            b += list(imm)
        r.shuffle(p)
        self.emit(cl + p + b)
        return os32

    def branch(self, op, size):
        self.items.append(('br', bytes(op), size))

    # ------------------------------------------------------------ straight-line instructions
    def simple(self):
        """one instruction that neither transfers control nor uses the stack"""
        r = self.r
        k = r.random()
        if k < 0.22:      # ALU
            op = r.choice([0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38]) | r.randrange(6)
            if op & 7 < 4:
                self.ins([op], mode='any', w=bool(op & 1), lock=(op & 2 == 0 and op < 0x38))
            else:
                self.ins([op], w=bool(op & 1), imm='z' if op & 1 else 'b')
        elif k < 0.29:    # group 1 immediate
            op = r.choice([0x80, 0x81, 0x82, 0x83])
            reg = r.randrange(8)
            self.ins([op], reg=reg, mode='any', w=bool(op & 1), imm='z' if op == 0x81 else 'b', lock=(reg != 7))
        elif k < 0.40:    # MOV forms
            c = r.randrange(8)
            if c == 0:
                op = r.choice([0x88, 0x89, 0x8A, 0x8B])
                self.ins([op], mode='any', w=bool(op & 1))
            elif c == 1:
                self.ins([0xB0 + r.randrange(8)], w=False, imm='b')
            elif c == 2:
                self.ins([0xB8 + self.rw()], imm='z')
            elif c == 3:
                op = r.choice([0xC6, 0xC7])
                self.ins([op], reg=0, mode='any', w=bool(op & 1), imm='z' if op & 1 else 'b')
            elif c == 4:
                op = r.choice([0xA0, 0xA1, 0xA2, 0xA3])
                as32 = r.random() < 0.12
                p = ([0x67] if as32 else []) + ([r.choice(SEGPFX)] if r.random() < 0.2 else [])
                os32 = bool(op & 1) and r.random() < 0.3
                if os32:
                    p.append(0x66)
                r.shuffle(p)
                self.emit(p + [op] + self.imm(2) + ([0, 0] if as32 else []))
            elif c == 5:
                self.ins([0x8C], reg=r.randrange(6), mode='any')
            elif c == 6:
                self.ins([0x8D], mode='mem', seg=False)
            else:         # mov ax, seg ; mov sreg, ax
                sel = r.choice(TSTSEL) if PM and r.random() < 0.3 else r.choice(DSEGS)
                self.emit([0xB8] + list(struct.pack('<H', sel)) +
                          [0x8E, 0xC0 | (r.choice([0, 3, 4, 5]) << 3)])
        elif k < 0.46:    # INC / DEC / group 3
            c = r.randrange(3)
            if c == 0:
                self.ins([r.choice([0x40, 0x48]) + self.rw()])
            elif c == 1:
                op = r.choice([0xFE, 0xFF])
                self.ins([op], reg=r.randrange(2), mode='any', w=bool(op & 1), lock=True)
            else:
                op = r.choice([0xF6, 0xF7])
                reg = r.randrange(8)
                self.ins([op], reg=reg, mode='any', w=bool(op & 1),
                         imm=None if reg >= 2 else ('z' if op & 1 else 'b'), lock=(reg in (2, 3)))
        elif k < 0.53:    # shifts / rotates
            op = r.choice([0xD0, 0xD1, 0xD2, 0xD3, 0xC0, 0xC1])
            self.ins([op], reg=r.randrange(8), mode='any', w=bool(op & 1), imm='b' if op < 0xD0 else None)
        elif k < 0.58:    # one-byte
            op = r.choice([0x27, 0x2F, 0x37, 0x3F, 0x9E, 0x9F, 0xD6, 0xF5, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD,
                           0x90, 0x9B, 0x98, 0x99, 0x98, 0x99] + [0x90 + x for x in (1, 2, 3, 5, 6, 7)])
            self.ins([op], a66=(op >= 0x91 and op <= 0x99))
        elif k < 0.62:
            c = r.randrange(5)
            if c == 0:
                self.emit([0xD4] + self.imm(1))
            elif c == 1:
                self.emit([0xD5] + self.imm(1))
            elif c == 2:
                # (with 67 EBX is cleaned first: 86Box does not limit-check XLAT, hardware does)
                a32 = r.random() < 0.1
                p = ([0x67] if a32 else []) + ([r.choice(SEGPFX)] if r.random() < 0.3 else [])
                self.emit(([0x66, 0x0F, 0xB7, 0xDB] if a32 else []) + p + [0xD7])
            elif c == 3:
                op = r.choice([0x84, 0x85, 0x86, 0x87, 0xA8, 0xA9])
                if op >= 0xA8:
                    self.ins([op], w=bool(op & 1), imm='z' if op & 1 else 'b')
                else:
                    self.ins([op], mode='reg' if op >= 0x86 and self.nw else 'any', w=bool(op & 1),
                             lock=(op >= 0x86))
            else:
                # (lockstep vs z486: DB /6 with a memory operand runs the reset microcode - a known
                #  z486 bug, reported - so that form becomes DB /6 with a register operand)
                op = 0xD8 + r.randrange(8)
                rg = r.randrange(8)
                self.ins([op], reg=rg, mode='reg' if (op == 0xDB and rg == 6) else 'any', a66=False)
        elif k < 0.70:    # string ops with a small count
            op = r.choice([0xA4, 0xA5, 0xA6, 0xA7, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0x6C, 0x6D, 0x6E, 0x6F])
            as32 = r.random() < 0.1
            cnt = r.randrange(0, 12)
            p = [r.choice([0xF2, 0xF3])] if r.random() < 0.7 else []
            if r.random() < 0.3:
                p.append(r.choice(SEGPFX))
            if (op & 1) and r.random() < 0.3:
                p.append(0x66)
            if as32:
                p.append(0x67)
            r.shuffle(p)
            # (mov ecx with a 67 prefix: the count register is ECX)
            ld = [0x66, 0xB9, cnt, 0, 0, 0] if as32 else [0xB9, cnt, 0]
            self.emit(ld + p + [op])
        elif k < 0.76:    # 186: IMUL imm, BOUND
            c = r.randrange(3)
            if c == 0:
                self.ins([0x69], mode='any', imm='z')
            elif c == 1:
                self.ins([0x6B], mode='any', imm='b')
            else:
                self.ins([0x62], mode='mem')
        elif k < 0.775:   # system registers (real mode)
            self.system()
        elif k < 0.97:    # 386 / 486 two-byte opcodes
            c = r.randrange(12)
            if c == 0:
                self.ins([0x0F, 0x90 + r.randrange(16)], reg=r.randrange(8), mode='any', w=False, a66=False)
            elif c == 1:
                op = r.choice([0xB6, 0xB7, 0xBE, 0xBF])
                self.ins([0x0F, op], mode='any', regw=True, rmw=bool(op & 1))
            elif c == 2:
                self.ins([0x0F, r.choice([0xA3, 0xAB, 0xB3, 0xBB])], mode='any', lock=True)
            elif c == 3:
                self.ins([0x0F, 0xBA], reg=r.randrange(4, 8), mode='any', imm='b', lock=True)
            elif c == 4:
                self.ins([0x0F, r.choice([0xBC, 0xBD])], mode='any')
            elif c == 5:  # SHLD / SHRD imm8: a 16-bit count above 16 is undefined
                os32 = r.random() < 0.4
                self.ins([0x0F, r.choice([0xA4, 0xAC])], mode='any', os=os32,
                         imm=[r.randrange(32) if os32 else r.randrange(17)])
            elif c == 6:  # ... by CL
                os32 = r.random() < 0.4
                self.ins([0x0F, r.choice([0xA5, 0xAD])], mode='any', os=os32,
                         pre=[0xB1, r.randrange(32) if os32 else r.randrange(17)])
            elif c == 7:
                self.ins([0x0F, 0xAF], mode='any')
            elif c == 8:
                op = r.choice([0xC0, 0xC1])
                self.ins([0x0F, op], mode='any', w=bool(op & 1), lock=True)
            elif c == 9:
                op = r.choice([0xB0, 0xB1])
                self.ins([0x0F, op], mode='any', w=bool(op & 1), lock=True)
            elif c == 10:
                self.emit([0x66, 0x0F, 0xC8 + self.rw()])
            else:         # LES / LDS / LSS / LFS / LGS from a far pointer built at DS:a
                os32 = r.random() < 0.3
                a = r.randrange(0xFFF0)
                op, sg = r.choice([([0xC4], None), ([0xC5], None), ([0x0F, 0xB4], None), ([0x0F, 0xB5], None),
                                   ([0x0F, 0xB2], SS)])
                sg = sg or r.choice(DSEGS)
                sa = a + (4 if os32 else 2)
                self.emit([0xC7, 0x06] + list(struct.pack('<HH', sa, sg)) + ([0x66] if os32 else []) + op +
                          [0x06 | (self.rw() << 3)] + list(struct.pack('<H', a)))
        elif k < 0.985:   # I/O
            c = r.randrange(2)
            if c == 0:
                op = 0xE4 + r.randrange(4)
                self.ins([op], w=bool(op & 1), imm='b')
            else:
                op = r.choice([0xEC, 0xED, 0xEE, 0xEF])
                self.ins([op], w=bool(op & 1))
        else:             # invalid forms: #UD
            c = r.randrange(4)
            if c == 0:
                self.emit([0x0F, 0xFF])
            elif c == 1:
                self.ins([0x63], mode='any', a66=False)                       # ARPL in real mode
            elif c == 2:
                self.ins([0xFE], reg=r.randrange(2, 8), mode='any', w=False)
            else:
                self.emit([0xF0, r.choice([0x90, 0x40, 0xF8, 0x9F])])         # LOCK on a non-lockable instruction

    def system(self):
        r = self.r
        a = r.randrange(0x7FF0)
        o = [0x66] if r.random() < 0.3 else []
        c = r.randrange(10)
        if PM and c in (1, 2):
            c = 0       # (protected mode: the tables stay)
        if c == 0:      # SGDT / SIDT
            self.emit(o + [0x0F, 0x01, 0x06 | (r.randrange(2) << 3)] + list(struct.pack('<H', a)))
        elif c == 1:    # LGDT (any value: no effect in real mode)
            self.emit([0xC7, 0x06] + list(struct.pack('<HH', a, r.randrange(65536))) +
                      [0x66, 0xC7, 0x06] + list(struct.pack('<HI', a + 2, r.randrange(1 << 32))) +
                      o + [0x0F, 0x01, 0x16] + list(struct.pack('<H', a)))
        elif c == 2:    # LIDT: one of the two vector tables (0, 0x800)
            self.emit([0xC7, 0x06] + list(struct.pack('<HH', a, r.choice([0x3FF, 0xFFFF]))) +
                      [0x66, 0xC7, 0x06] + list(struct.pack('<HI', a + 2, r.choice([0, 0x800]))) +
                      o + [0x0F, 0x01, 0x1E] + list(struct.pack('<H', a)))
        elif c == 3:    # SMSW r / m
            if r.random() < 0.5:
                self.emit(o + [0x0F, 0x01, 0xE0 | self.rw()])
            else:
                self.emit([0x0F, 0x01, 0x26] + list(struct.pack('<H', a)))
        elif c == 4:    # LMSW (PE stays clear; MP / EM / TS random: ESC / WAIT may raise #NM)
            self.emit([0xB8] + list(struct.pack('<H', r.randrange(65536) & 0xFFFE)) + [0x0F, 0x01, 0xF0])
        elif c == 5:
            self.emit([0x0F, 0x06])                                         # CLTS
        elif c == 6:    # MOV r32, CR0 / CR2 / CR3
            self.emit([0x0F, 0x20, 0xC0 | (r.choice([0, 2, 3]) << 3) | self.rw()])
        elif c == 7:    # MOV CR0, r32: PE / PG clear, CD / NW valid
            v = r.randrange(1 << 32) & ~0x80000001
            if PM:
                v |= 1
            if PG:
                v |= 0x80010000
            if (v >> 29) & 3 == 1 or not self.nw:
                v &= ~(1 << 29)
            self.emit([0x66, 0xB8] + list(struct.pack('<I', v)) + [0x0F, 0x22, 0xC0])
        elif c == 8:    # MOV CR2 / CR3, r32
            if PG and r.random() < 0.6:     # (paging: CR3 reloaded with its value)
                x = self.rw()
                self.emit([0x0F, 0x20, 0xD8 | x, 0x0F, 0x22, 0xD8 | x])
            else:
                self.emit([0x0F, 0x22, 0xC0 | ((2 if PG else r.choice([2, 3])) << 3) | self.rw()])
        else:           # undefined CR, INVLPG, ESC / WAIT
            self.emit(r.choice([[0x0F, 0x20, 0xC8 | r.randrange(8)], [0x0F, 0x22, 0xE0 | r.randrange(8)],
                                [0x0F, 0x01, 0x3E] + list(struct.pack('<H', a)), [0x9B],
                                [0xD9, 0xC0 | r.randrange(64)]]))

    # ------------------------------------------------------------ everything
    def one(self):
        r = self.r
        k = r.random()
        if k < 0.70:
            self.simple()
        elif k < 0.80:    # stack
            c = r.randrange(11)
            if c == 0:
                self.ins([0x50 + r.randrange(8)])
            elif c == 1:
                self.ins([0x58 + self.rw()])
            elif c == 2:
                self.ins([r.choice([[0x06], [0x0E], [0x16], [0x1E], [0x0F, 0xA0], [0x0F, 0xA8]])][0])
            elif c == 3:  # push seg ; pop data seg  (same operand size)
                os = [0x66] if r.random() < 0.3 else []
                self.emit(os + r.choice([[0x06], [0x16], [0x1E], [0x0F, 0xA0], [0x0F, 0xA8]]) +
                          os + r.choice([[0x07], [0x1F], [0x0F, 0xA1], [0x0F, 0xA9]]))
            elif c == 4:
                self.emit([0x16, 0x17] + [r.choice([0x40, 0x90, 0xF8])])       # push ss ; pop ss ; (inhibited boundary)
            elif c == 5:
                self.ins([0xFF], reg=6, mode='any')
            elif c == 6:  # (16-bit addressing: 86Box does not undo the pop when the store faults,
                          #  the 386EX captures of the 80386 suite and the core do)
                if r.random() < 0.5:
                    self.ins([0x8F], reg=0, mode='reg')
                else:
                    self.emit(([r.choice(SEGPFX)] if r.random() < 0.2 else []) + [0x8F, 0x06] +
                              list(struct.pack('<H', r.randrange(0xFFF0))))
            elif c == 7:
                self.ins([r.choice([0x68, 0x6A, 0x9C])][0:1], imm=None) if False else None
                op = r.choice([0x68, 0x6A, 0x9C])
                self.ins([op], imm={0x68: 'z', 0x6A: 'b', 0x9C: None}[op])
            elif c == 8:  # push imm ; popf   (TF clear)
                fl = r.randrange(65536) & ~0x0100
                if r.random() < 0.3:
                    self.emit([0x66, 0x68] + list(struct.pack('<I', fl | (r.randrange(4) << 16))) + [0x66, 0x9D])
                else:
                    self.emit([0x68] + list(struct.pack('<H', fl)) + [0x9D])
            elif c == 9:
                self.ins([r.choice([0x60, 0x61])])
            else:         # enter n, level ; leave
                os = [0x66] if r.random() < 0.3 else []
                # (level > 1 reads the old frame at BP - 2k / 4k: BP is set from SP so that it does not
                #  wrap, 86Box does not limit-check those reads)
                lv = r.choice([0, 0, 1, 1, 2, 3, 5])
                self.emit(([0x89, 0xE5] if lv > 1 else []) + os + [0xC8, r.randrange(0, 64) * 2, 0, lv] + os + [0xC9])
        elif k < 0.90:    # conditional / loop branches
            c = r.randrange(6)
            if c == 0:
                self.branch([0x70 + r.randrange(16)], 1)
            elif c == 1:
                self.branch([0x0F, 0x80 + r.randrange(16)], 2)
            elif c == 2:
                self.branch([0x66, 0x0F, 0x80 + r.randrange(16)], 4)
            elif c == 3:
                self.emit([0xB9, r.randrange(0, 6), 0])
                self.branch([0xE0 + r.randrange(4)], 1)
            elif c == 4:
                self.emit([0x66, 0xB9, r.randrange(0, 6), 0, 0, 0])
                self.branch([0x67, 0xE0 + r.randrange(4)], 1)
            else:
                self.branch([0xEB], 1)
        elif k < 0.96:    # jumps / calls
            c = r.randrange(8)
            if c == 0:
                self.branch([0xE9], 2)
            elif c == 1:
                self.branch([0x66, 0xE9], 4)
            elif c == 2:
                self.branch([0xE8], 2)
            elif c == 3:  # mov bx, target ; jmp / call bx
                self.items.append(('abs', bytes([0xBB]), bytes([0xFF, r.choice([0xD3, 0xE3])])))
            elif c == 4:  # jmp far CS:target
                self.items.append(('abs', bytes([0xEA]), struct.pack('<H', CS)))
            elif c == 5:  # call L ; jmp over ; L: body ; ret
                self.callret(False, r.random() < 0.3)
            elif c == 6:  # push cs ; call L ; jmp over ; L: body ; retf
                self.callret(True, False)
            else:         # mov [disp16], target ; jmp / call [disp16]
                a = r.randrange(0xFFF0)
                self.items.append(('abs', bytes([0xC7, 0x06]) + struct.pack('<H', a),
                                   bytes([0xFF, r.choice([0x16, 0x26])]) + struct.pack('<H', a)))
        else:             # software interrupts
            c = r.randrange(3)
            if c == 0:
                self.emit([0xCC])
            elif c == 1:
                self.emit([0xCD, r.randrange(256)])
            else:
                self.emit([0xCE])

    def callret(self, far, os32):
        r = self.r
        g2 = Gen(r.randrange(1 << 30))
        g2.nw = self.nw
        for _ in range(r.randrange(0, 4)):
            g2.simple()
        body = b''.join(x[1] for x in g2.items)
        o = [0x66] if os32 else []
        jl = 5 if os32 else 3                       # length of the jmp over
        call = ([0x0E] if far else []) + o + [0xE8] + list(struct.pack('<i' if os32 else '<h', jl))
        jmp = o + [0xE9] + list(struct.pack('<i' if os32 else '<h', len(body) + 1 + len(o)))
        if os32:
            jl = len(jmp)
            call = o + [0xE8] + list(struct.pack('<i', jl))
        self.emit(bytes(call) + bytes(jmp) + body + bytes(o + [0xCB if far else 0xC3]))

    def build(self, limit):
        r = self.r
        size = 0
        while size < limit:
            n = len(self.items)
            self.one()
            for it in self.items[n:]:
                size += len(it[1]) + (it[2] if it[0] == 'br' else 2 + len(it[2]) if it[0] == 'abs' else 0)
        addr = 0
        starts = []
        for it in self.items:
            starts.append(addr)
            addr += len(it[1]) + (it[2] if it[0] == 'br' else 2 + len(it[2]) if it[0] == 'abs' else 0)
        assert addr < H_FAULT - 16, addr
        code = bytearray(b'\x90' * 0x10000)
        for a, it in zip(starts, self.items):
            if it[0] == 'b':
                code[a:a + len(it[1])] = it[1]
            elif it[0] == 'br':
                nxt = a + len(it[1]) + it[2]
                cands = [s for s in starts if -128 <= s - nxt <= 127] if it[2] == 1 else starts
                d = r.choice(cands) - nxt
                # (a 16-bit displacement wraps inside the 64 KB segment)
                code[a:nxt] = it[1] + (struct.pack('<b', d) if it[2] == 1 else struct.pack('<H', d & 0xFFFF)
                                       if it[2] == 2 else struct.pack('<i', d))
            else:
                b = it[1] + struct.pack('<H', r.choice(starts)) + it[2]
                code[a:a + len(b)] = b
        code[addr:addr + 3] = bytes([0xE9]) + struct.pack('<H', -(addr + 3) & 0xFFFF)       # back to the start
        # fault handler: resume at the next entry of a table of instruction starts
        h = bytes([0x53, 0x55, 0x89, 0xE5,                                  # push bx ; push bp ; mov bp, sp
                   0x2E, 0x8B, 0x1E]) + struct.pack('<H', H_CTR) + \
            bytes([0x43, 0x43, 0x81, 0xE3, 0xFE, 0x01,                      # inc bx ; inc bx ; and bx, 1FE
                   0x2E, 0x89, 0x1E]) + struct.pack('<H', H_CTR) + \
            bytes([0x2E, 0x8B, 0x9F]) + struct.pack('<H', H_TABLE) + \
            bytes([0x89, 0x5E, 0x04, 0x5D, 0x5B, 0xCF])                     # mov [bp+4], bx ; pop bp ; pop bx ; iret
        code[H_FAULT:H_FAULT + len(h)] = h
        for i in range(256):
            code[H_TABLE + 2 * i:H_TABLE + 2 * i + 2] = struct.pack('<H', r.choice(starts))
        code[H_CTR:H_CTR + 2] = b'\0\0'
        code[H_IRET] = 0xCF
        if PM:
            # prologue: pushf, push eax, lgdt / lidt cs:[..], CR0.PE, pop eax, popf, jmp 1000:0000
            pro = bytes([0x9C, 0x66, 0x50, 0x2E, 0x66, 0x0F, 0x01, 0x16]) + struct.pack('<H', H_GDTR) + \
                  bytes([0x2E, 0x66, 0x0F, 0x01, 0x1E]) + struct.pack('<H', H_IDTR)
            if PG:      # CR3, then PE | WP | PG
                pro += bytes([0x66, 0xB8]) + struct.pack('<I', PD_ADDR) + bytes([0x0F, 0x22, 0xD8]) + \
                       bytes([0x0F, 0x20, 0xC0, 0x66, 0x0D]) + struct.pack('<I', 0x80010001)
            else:
                pro += bytes([0x0F, 0x20, 0xC0, 0x0C, 0x01])
            pro += bytes([0x0F, 0x22, 0xC0, 0x66, 0x58, 0x9D, 0xEA, 0x00, 0x00]) + struct.pack('<H', CS)
            code[H_PRO:H_PRO + len(pro)] = pro
            code[H_GDTR:H_GDTR + 6] = struct.pack('<HI', 0xB007, 0x80000)
            code[H_IDTR:H_IDTR + 6] = struct.pack('<HI', 0x7FF, 0x8C000)
            # error code stubs: drop it, then the fault handler / IRET
            code[H_EC1:H_EC1 + 6] = bytes([0x83, 0xC4, 0x02, 0xE9]) + struct.pack('<h', H_FAULT - (H_EC1 + 6))
            code[H_EC2:H_EC2 + 4] = bytes([0x83, 0xC4, 0x02, 0xCF])
        if PG:
            # #PF: PTE of CR2 |= P | W (table through selector 58), INVLPG (flat 50), restart
            pf = bytes([0x66, 0x50, 0x1E,                                   # push eax ; push ds
                        0xB8]) + struct.pack('<H', SEL_PT) + bytes([0x8E, 0xD8,   # mov ax, 58 ; mov ds, ax
                        0x0F, 0x20, 0xD0, 0x66, 0xC1, 0xE8, 0x0C,               # mov eax, cr2 ; shr eax, 12
                        0x67, 0x66, 0x83, 0x0C, 0x85, 0, 0, 0, 0, 0x03,         # or dword [eax*4], 3
                        0xB8]) + struct.pack('<H', SEL_FLAT) + bytes([0x8E, 0xD8,  # mov ax, 50 ; mov ds, ax
                        0x0F, 0x20, 0xD0, 0x67, 0x0F, 0x01, 0x38,               # mov eax, cr2 ; invlpg [eax]
                        0x1F, 0x66, 0x58, 0x83, 0xC4, 0x02, 0xCF])              # pop ds ; pop eax ; add sp, 2 ; iret
            code[H_PF:H_PF + len(pf)] = pf
        return bytes(code)


def main():
    av = [x for x in sys.argv if not x.startswith('--')]
    out, seed = av[1], int(av[2])
    nret = int(av[3]) if len(av) > 3 else 3000
    g = Gen(seed)
    code = g.build(0xC000)
    r = random.Random(seed ^ 0x5A5A)
    gpr = [r.randrange(1 << 32) if r.random() < 0.5 else r.randrange(1 << 16) for _ in range(8)]
    gpr[4] = r.randrange(65536) & 0xFFFE
    seg = [ES, CS, SS, DS, FS, GS]
    ivt = [H_FAULT if v in FAULT_VECS else H_IRET for v in range(256)]
    if PM:          # (vectors with an error code: through a stub that drops it)
        ivt = [H_EC1 if v in (12, 13) else H_EC2 if v in (10, 11, 14, 17) else ivt[v] for v in range(256)]
    if PG:
        ivt[14] = H_PF
    with open(out, 'wb') as f:
        f.write((b'RPG3' if PG else b'RPM3' if PM else b'R386') + struct.pack('<II', seed, nret) + struct.pack('<8I', *gpr) +
                struct.pack('<6H', *seg) + struct.pack('<II', H_PRO if PM else 0, 0x0002 | (r.randrange(2) << 10)) +
                struct.pack('<256H', *ivt) + code)


if __name__ == '__main__':
    main()
