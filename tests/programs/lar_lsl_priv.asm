; lar_lsl_priv.asm - LAR/LSL/VERR/VERW privilege at CPL 3
;
; i486 PRM (LAR, LSL, VERR, VERW): a non-conforming segment or a system
; descriptor is visible only when DPL >= CPL and DPL >= RPL; conforming
; code segments are visible at any privilege. Win95 validates selectors
; this way (IsBadReadPtr and friends), so a DPL-0 selector reported valid
; to ring 3 turns into a GPF later.
;
; Ring 3 (IOPL 3, for the result port) runs each instruction on a table of
; selectors and records ZF; the result is compared with the expected bits.
; Port 0xE4 on failure: (instruction << 24) | got, then expected.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CONF0   equ 0x18    ; conforming readable code, DPL 0
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28    ; available 386 TSS, DPL 0
SEL_CODE3   equ 0x30
SEL_D0      equ 0x38    ; data, DPL 0
SEL_D3      equ 0x40    ; data, DPL 3
SEL_D2      equ 0x48    ; data, DPL 2
SEL_GATE0   equ 0x50    ; 386 call gate, DPL 0
SEL_GATE3   equ 0x58    ; 386 call gate, DPL 3
SEL_TSS3    equ 0x60    ; available 386 TSS, DPL 3

STACK0_TOP  equ 0x3000
STACK3_TOP  equ 0x4000

start:
    cli
    lgdt [cs:gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm_entry

BITS 32
pm_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword 0x00003002       ; IOPL 3
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

; Selectors tested, in bit order
;  0 D0 RPL0   1 D3 RPL0   2 D3 RPL3   3 D2 RPL0   4 D2 RPL3
;  5 CONF0 RPL0  6 CONF0 RPL3  7 TSS DPL0  8 GATE0  9 GATE3  10 TSS3
NSEL equ 11
%macro RUN 2                    ; %1: instruction mnemonic, %2: index
    xor ebx, ebx
    xor esi, esi
%%loop:
    movzx eax, word [sels + esi*2]
    xor ecx, ecx
    %1 ecx, ax
    jnz %%nz
    bts ebx, esi
%%nz:
    inc esi
    cmp esi, NSEL
    jb %%loop
    cmp ebx, [expect + %2*4]
    je %%ok
    mov eax, %2
    shl eax, 24
    or eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [expect + %2*4]
    out dx, eax
    jmp fail
%%ok:
%endmacro

%macro RUNV 2                   ; VERR/VERW
    xor ebx, ebx
    xor esi, esi
%%loop:
    movzx eax, word [sels + esi*2]
    %1 ax
    jnz %%nz
    bts ebx, esi
%%nz:
    inc esi
    cmp esi, NSEL
    jb %%loop
    cmp ebx, [expect + %2*4]
    je %%ok
    mov eax, %2
    shl eax, 24
    or eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [expect + %2*4]
    out dx, eax
    jmp fail
%%ok:
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    RUN lar, 0
    RUN lsl, 1
    RUNV verr, 2
    RUNV verw, 3
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    jmp $

fail:
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp $

align 4
sels:
    dw SEL_D0, SEL_D3, SEL_D3|3, SEL_D2, SEL_D2|3
    dw SEL_CONF0, SEL_CONF0|3, SEL_TSS, SEL_GATE0, SEL_GATE3, SEL_TSS3
align 4
expect:
    ; LAR: D3 x2, CONF0 x2, GATE3, TSS3
    dd (1<<1)|(1<<2)|(1<<5)|(1<<6)|(1<<9)|(1<<10)
    ; LSL: no gates
    dd (1<<1)|(1<<2)|(1<<5)|(1<<6)|(1<<10)
    ; VERR: D3 x2, readable conforming code
    dd (1<<1)|(1<<2)|(1<<5)|(1<<6)
    ; VERW: writable data only
    dd (1<<1)|(1<<2)

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x00CF9F010000FFFF       ; 0x18 conforming readable, DPL 0
    dq 0x00CFF3010000FFFF       ; 0x20 data3
    dw 0x0067                   ; 0x28 TSS, DPL 0
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CFFB010000FFFF       ; 0x30 code3
    dq 0x00CF93010000FFFF       ; 0x38 data, DPL 0
    dq 0x00CFF3010000FFFF       ; 0x40 data, DPL 3
    dq 0x00CFD3010000FFFF       ; 0x48 data, DPL 2
    dw 0                        ; 0x50 386 call gate, DPL 0
    dw SEL_CODE0
    db 0
    db 0x8C
    dw 0
    dw 0                        ; 0x58 386 call gate, DPL 3
    dw SEL_CODE0
    db 0
    db 0xEC
    dw 0
    dw 0x0067                   ; 0x60 TSS, DPL 3
    dw tss386b
    db 0x01
    db 0xE9
    db 0x00
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 4
tss386:
    dd 0
    dd STACK0_TOP
    dd SEL_DATA0
    times 22 dd 0
    dw 0
    dw 104
tss386b:
    times 26 dd 0
