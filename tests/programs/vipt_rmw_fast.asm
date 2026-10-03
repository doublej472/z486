; RD_FAST/WR_FAST cached RMW regression.  The first clean-page operation must
; replay through paging; the remaining aligned operations use the generated
; 04A/04E overlays after the page and cache line are warm.

BITS 32
org 0

STATUS_PORT equ 0xE0
FLAGS_MASK  equ 0x000008D5       ; OF,SF,ZF,AF,PF,CF

MCLEAN  equ 0x1000
MADD    equ 0x1040
MOR     equ 0x1044
MADC    equ 0x1048
MSBB    equ 0x104c
MAND    equ 0x1050
MSUB    equ 0x1054
MXOR    equ 0x1058
MINC    equ 0x105c
MDEC    equ 0x1060
MNOT    equ 0x1064
MNEG    equ 0x1068
MPART   equ 0x106c
MUNAL   equ 0x1071
MLOCK   equ 0x1078

start:
    ; A read warms a still-clean page.  The first INC must reject RD_FAST,
    ; take the authoritative walker path, and set the PTE dirty bit.
    mov eax, [MCLEAN]
    inc dword [MCLEAN]
    cmp dword [MCLEAN], 1
    jne fail1

    mov dword [MADD],  0x100
    mov dword [MOR],   0x100
    mov dword [MADC],  5
    mov dword [MSBB],  10
    mov dword [MAND],  0xff
    mov dword [MSUB],  10
    mov dword [MXOR],  0xaa55
    mov dword [MINC],  0xffffffff
    mov dword [MDEC],  0
    mov dword [MNOT],  0x12345678
    mov dword [MNEG],  1
    mov dword [MPART], 0xa1b2c3d4
    mov dword [MUNAL], 0x10203040
    mov dword [MLOCK], 7

    ; Drain posted initialization stores, then warm every source line.
    times 32 nop
    mov eax, [MADD]
    mov eax, [MOR]
    mov eax, [MADC]
    mov eax, [MSBB]
    mov eax, [MAND]
    mov eax, [MSUB]
    mov eax, [MXOR]
    mov eax, [MINC]
    mov eax, [MDEC]
    mov eax, [MNOT]
    mov eax, [MNEG]
    mov eax, [MPART]
    mov eax, [MUNAL]
    mov eax, [MLOCK]
    times 8 nop

    mov eax, 3
    add dword [MADD], eax
    cmp dword [MADD], 0x103
    jne fail2

    mov eax, 0x0f
    or dword [MOR], eax
    cmp dword [MOR], 0x10f
    jne fail2

    mov eax, 3
    stc
    adc dword [MADC], eax
    cmp dword [MADC], 9
    jne fail2

    mov eax, 3
    stc
    sbb dword [MSBB], eax
    cmp dword [MSBB], 6
    jne fail2

    mov eax, 0x0f
    and dword [MAND], eax
    cmp dword [MAND], 0x0f
    jne fail2

    mov eax, 3
    sub dword [MSUB], eax
    cmp dword [MSUB], 7
    jne fail2

    mov eax, 0x00ff
    xor dword [MXOR], eax
    cmp dword [MXOR], 0xaaaa
    jne fail2

    ; INC/DEC preserve carry; NOT preserves every arithmetic flag.
    stc
    inc dword [MINC]
    jnc fail3
    cmp dword [MINC], 0
    jne fail3

    clc
    dec dword [MDEC]
    jc fail3
    cmp dword [MDEC], 0xffffffff
    jne fail3

    mov eax, 0x1234
    cmp eax, eax
    stc
    pushfd
    pop ebx
    not dword [MNOT]
    pushfd
    pop ecx
    xor ebx, ecx
    and ebx, FLAGS_MASK
    jnz fail3
    cmp dword [MNOT], 0xedcba987
    jne fail3

    neg dword [MNEG]
    jnc fail3
    cmp dword [MNEG], 0xffffffff
    jne fail3

    ; Byte/word lanes must merge without damaging neighbouring bytes.
    mov al, 1
    add byte [MPART + 1], al
    mov ax, 0x10
    add word [MPART + 2], ax
    cmp dword [MPART], 0xa1c2c4d4
    jne fail4

    ; Unaligned and LOCKed forms are deliberately ineligible and must use the
    ; unchanged authoritative routines.
    mov eax, 1
    add dword [MUNAL], eax
    cmp dword [MUNAL], 0x10203041
    jne fail5

    mov eax, 2
    lock add dword [MLOCK], eax
    cmp dword [MLOCK], 9
    jne fail5

    ; Same-word chains prove store-to-next-RD_FAST forwarding.
    mov eax, 1
    add dword [MADD], eax
    add dword [MADD], eax
    add dword [MADD], eax
    cmp dword [MADD], 0x106
    jne fail6

pass:
    mov al, 1
    out STATUS_PORT, al
    hlt

fail1: mov eax, 7        ; status 1 means pass
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
fail:
    out STATUS_PORT, al
    hlt
