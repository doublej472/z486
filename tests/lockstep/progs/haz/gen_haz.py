#!/usr/bin/env python3
"""Directed pipeline-hazard programs for the lockstep (nasm source on stdout).
Each case: set registers, the producer, 0-3 filler instructions, the consumer,
then store every GPR and FLAGS to a fresh slot of the result area (ES:DI)."""
import random, sys
kind = sys.argv[1]; seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
r = random.Random(seed)
R32 = ['eax', 'ecx', 'edx', 'ebx', 'ebp', 'esi', 'edi']     # (no esp)
R16 = ['ax', 'cx', 'dx', 'bx', 'bp', 'si', 'di']
out = ['org 0', 'times 0x100 db 0', 'bits 16', 'start:', '  cld', '  mov ax, 0x2000', '  mov ds, ax', '  mov ax, 0x3000', '  mov es, ax', '  xor di, di', '  mov sp, 0xfff0']
def init():
    for x in R32:
        if x == 'edi': continue
        out.append('  mov %s, 0x%08x' % (x, r.randrange(1 << 32) if r.random() < 0.5 else r.randrange(0x8000) * 2))
def fill(n):
    for _ in range(n):
        out.append(r.choice(['  nop', '  mov dx, dx', '  xchg cx, cx', '  lea dx, [bx]']))
def dump():
    out.append('  push edi')
    out.append('  mov di, [cs:resptr]')
    for x in ['eax', 'ecx', 'edx', 'ebx', 'ebp', 'esi']:
        out.append('  mov [es:di], %s' % x); out.append('  add di, 4')
    out.append('  pop edx'); out.append('  mov [es:di], edx'); out.append('  add di, 4')
    out.append('  pushfd'); out.append('  pop edx'); out.append('  mov [es:di], edx'); out.append('  add di, 4')
    out.append('  mov [cs:resptr], di')
    out.append('  mov edi, edx')
for c in range(int(sys.argv[3]) if len(sys.argv) > 3 else 200):
    init()
    out.append('  mov edi, 0x%08x' % r.randrange(1 << 32))
    g = r.randrange(4)
    if kind == 'shld':
        op = r.choice(['shld', 'shrd'])
        d, s = r.choice(R32), r.choice(R32)
        cnt = r.randrange(1, 32)
        form = r.randrange(4)
        if form == 0:      # producer writes the SHLD source / destination right before it
            p = r.choice([d, s])
            out.append('  mov %s, 0x%08x' % (p, r.randrange(1 << 32)))
            fill(g)
            out.append('  %s %s, %s, %d' % (op, d, s, cnt))
        elif form == 1:    # SHLD result consumed right after (ALU / address)
            out.append('  %s %s, %s, %d' % (op, d, s, cnt))
            fill(g)
            c2 = r.choice(R32)
            if r.random() < 0.5:
                out.append('  add %s, %s' % (c2, d))
            else:
                out.append('  and %s, 0xfffe' % d)
                fill(r.randrange(2))
                out.append('  mov %s, [%s]' % (r.choice(R16[:4]), {'eax':'bx','ecx':'bx','edx':'bx','ebx':'bx','ebp':'bp','esi':'si','edi':'di'}[d]) if d in ('ebx','ebp','esi','edi') else '  add %s, %s' % (c2, d))
        elif form == 2:    # load into a SHLD operand right before it
            p = r.choice([d, s])
            out.append('  mov %s, [0x%04x]' % (p, r.randrange(0x8000) * 2))
            fill(g)
            out.append('  %s %s, %s, %d' % (op, d, s, cnt))
        else:              # by CL, with CL just written
            out.append('  mov cl, %d' % r.randrange(32))
            fill(g)
            out.append('  %s %s, %s, cl' % (op, d if d != 'ecx' else 'edx', s))
    elif kind == 'adc':
        op = r.choice(['adc', 'sbb'])
        size = r.choice(['byte', 'word', 'dword'])
        a = r.randrange(0x8000) * 2
        prod = r.choice(['  stc', '  clc', '  cmc', '  add %s, %s' % (r.choice(R32), r.choice(R32)),
                         '  sub %s, 0x%x' % (r.choice(R16), r.randrange(65536)), '  cmp %s, %s' % (r.choice(R16), r.choice(R16)),
                         '  shr %s, 1' % r.choice(R32), '  neg %s' % r.choice(R16)])
        out.append(prod)
        fill(g)
        imm = r.randrange(256) if size == 'byte' or r.random() < 0.5 else r.randrange(65536)
        if size == 'byte': imm &= 0xff
        out.append('  %s %s [0x%04x], %s0x%x' % (op, size, a, 'byte ' if (size != 'byte' and imm < 128 and r.random() < 0.5) else '', imm))
        out.append('  mov eax, [0x%04x]' % a)
    elif kind == 'flagsrd':   # every flag consumer right after a flag producer
        prod = r.choice(['  stc', '  clc', '  cmc', '  add %s, %s' % (r.choice(R32), r.choice(R32)), '  inc %s' % r.choice(R16),
                         '  sub %s, 0x%x' % (r.choice(R16), r.randrange(65536)), '  shl %s, 1' % r.choice(R32), '  neg %s' % r.choice(R16)])
        cons = r.choice(['  adc %s, 0x%x' % (r.choice(R16), r.randrange(65536)), '  sbb %s, %s' % (r.choice(R32), r.choice(R32)),
                         '  adc word [0x%04x], 0x%x' % (r.randrange(0x8000) * 2, r.randrange(65536)),
                         '  sbb dword [0x%04x], %s' % (r.randrange(0x8000) * 2, r.choice(R32)),
                         '  adc %s, [0x%04x]' % (r.choice(R16), r.randrange(0x8000) * 2),
                         '  rcl %s, 1' % r.choice(R16), '  rcr word [0x%04x], 1' % (r.randrange(0x8000) * 2),
                         '  setc al', '  lahf', '  pushf', '  cmc', '  salc' if False else '  setbe dl', '  adc byte [0x%04x], 0x%x' % (r.randrange(0x8000) * 2, r.randrange(256))])
        out.append(prod); fill(g); out.append(cons)
        if 'pushf' in cons: out.append('  pop dx')
    dump()
out += ['  hlt', 'align 2', 'resptr: dw 0']
print('\n'.join(out))
