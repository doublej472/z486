; Registered VIPT ALU register,memory regressions.  The aligned cases exercise
; the direct hit pipeline; unaligned/cold and ordered-store cases exercise the
; same metadata through paging fallback.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

M3       equ 0x1000
M4       equ 0x1004
MONE     equ 0x1008
MOR      equ 0x100c
MAND     equ 0x1010
MXOR     equ 0x1014
MWORD    equ 0x1018
MBYTE    equ 0x101a
MDELTA   equ 0x101c
MALIAS   equ 0x1040
MCROSS   equ 0x1051
TARGET   equ 0x2100
MCOLD    equ 0x3000

start:
    mov dword [M3], 3
    mov dword [M4], 4
    mov dword [MONE], 0xffffffff
    mov dword [MOR], 0x000000f0
    mov dword [MAND], 0x00000ff0
    mov dword [MXOR], 0x00000ff0
    mov word  [MWORD], 0x0102
    mov byte  [MBYTE], 2
    mov dword [MDELTA], 0x100
    mov dword [TARGET], 0x51a7c001
    mov dword [MCROSS], 0x10203040
    mov dword [MCOLD], 0x11111111

    ; Drain stores and warm the aligned direct-hit source lines.
    times 32 nop
    mov edx, [M3]
    mov edx, [M4]
    mov edx, [MONE]
    mov edx, [MOR]
    mov edx, [MAND]
    mov edx, [MXOR]
    mov edx, [MWORD]
    mov edx, [MDELTA]
    mov edx, [TARGET]
    times 8 nop

    ; 1. Every arithmetic/logical opcode in the register,memory class.
    mov eax, 0x10
    add eax, [M3]
    cmp eax, 0x13
    jne fail1

    mov eax, 0x1000
    or eax, [MOR]
    cmp eax, 0x10f0
    jne fail1

    mov eax, 5
    stc
    adc eax, [M3]
    cmp eax, 9
    jne fail1

    mov eax, 10
    stc
    sbb eax, [M3]
    cmp eax, 6
    jne fail1

    mov eax, 0xf0f0
    and eax, [MAND]
    cmp eax, 0x00f0
    jne fail1

    mov eax, 10
    sub eax, [M3]
    cmp eax, 7
    jne fail1

    mov eax, 0xaa55
    xor eax, [MXOR]
    cmp eax, 0xa5a5
    jne fail1

    ; 2. Partial-register writes merge once at WB.
    mov eax, 0x12341056
    add ah, [MBYTE]
    cmp eax, 0x12341256
    jne fail2

    mov eax, 0xabcd1000
    add ax, [MWORD]
    cmp eax, 0xabcd1102
    jne fail2

    ; 3. The direct result and flags feed immediate successors.
    mov eax, 0xffffffff
    add eax, [M3]
    jnc fail3
    mov ebx, eax
    cmp ebx, 2
    jne fail3

    mov eax, 0xffffffff
    add eax, [M3]
    mov ebx, 10
    adc ebx, [M4]
    cmp ebx, 15
    jne fail3

    ; 4. Older direct load and direct ALU tokens may overlap in order.
    mov eax, [M4]
    add eax, [M3]
    add eax, [M4]
    cmp eax, 11
    jne fail4

    ; 5. Independent direct ALUs keep their own destination metadata.
    mov eax, 1
    mov ebx, 10
    add eax, [M3]
    sub ebx, [M4]
    cmp eax, 4
    jne fail5
    cmp ebx, 6
    jne fail5

    ; 6. A direct ALU result may become the next effective-address base.
    mov esi, 0x2000
    add esi, [MDELTA]
    mov ebx, [esi]
    cmp ebx, 0x51a7c001
    jne fail6

    ; 7. An older posted store cannot be bypassed by the direct ALU read.
    mov dword [MALIAS], 42
    mov eax, 1
    add eax, [MALIAS]
    cmp eax, 43
    jne fail7

    ; 8. A crossing dword and a cold line retain ALU metadata through paging.
    mov eax, 1
    add eax, [MCROSS]
    cmp eax, 0x10203041
    jne fail8

    mov eax, 2
    add eax, [MCOLD]
    cmp eax, 0x11111113
    jne fail8

pass:
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail1: mov eax, 1
    jmp fail
fail2: mov eax, 2
    jmp fail
fail3: mov eax, 3
    jmp fail
fail4: mov eax, 4
    jmp fail
fail5: mov eax, 5
    jmp fail
fail6: mov eax, 6
    jmp fail
fail7: mov eax, 7
    jmp fail
fail8: mov eax, 8
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
