; invlpg_ss_limit_gp - INVLPG at CPL3 whose operand is beyond the SS limit
; raises #GP(0) (privilege), not #SS(0)
;
; 486 PRM INVLPG: the only protected-mode exceptions are #GP(0) for CPL!=0
; and #UD for a register operand.  The core also limit-checks the operand and
; ss_fault_r selects #SS(0) when that check fails on SS, even though the
; privilege #GP(0) is raised in the same cycle.  (Derived from cpl3_priv_gp;
; the ring-3 SS has a byte-granular 64 KiB limit.)
;
; INVLPG, INVD, WBINVD and MOV to/from debug, test and control registers are
; CPL0-only.  Their #GP(0) shares the fault path with segment-limit faults,
; whose #SS/#GP choice follows the segment of the current access.  A stack
; operand (INVLPG [ESP]) or a preceding PUSH left that segment at SS, which
; turned the privilege fault into #SS(0).
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_STACK3  equ 0x30
R3_STACK    equ 0x00003000
R0_STACK    equ 0x00014000

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, R0_STACK
    mov ax, SEL_TSS
    ltr ax
    push dword SEL_STACK3 | 3
    push dword R3_STACK
    push dword 0x202
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

%macro PRIV 1+
    mov edi, %%after
    inc ebx
    push eax
    %1
%%after:
    cmp ebp, ebx
    jne bad3
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    xor ebx, ebx
    xor ebp, ebp
    PRIV invlpg [esp+0x20000]        ; beyond the 64 KiB SS limit
    PRIV invlpg [ebp+0x20000]        ; EBP base: SS as well
    int 0x21
bad3:
    int 0x22

gp_handler:
    cmp dword [esp], 0
    jne bad0
    inc ebp
    mov [esp+4], edi
    add esp, 4
    iretd
ss_handler:
    mov eax, 0x5500
    add eax, ebx
    jmp report_fail
bad0:
    mov eax, 0x6600
    add eax, ebx
    jmp report_fail

pass_handler:
    mov al, 1
    out STATUS_PORT, al
    hlt
fail_handler:
    mov eax, ebx
report_fail:
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
    dq 0x00cffb010000ffff
    dq 0x00cff3000000ffff
tss_desc:
    dw 0x0067
    dw tss
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x0040f3000000ffff            ; 30: ring-3 stack, byte limit FFFFh, B=1
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

%macro GATE 2
    dw %1
    dw SEL_CODE0
    db 0, %2
    dw 0
%endmacro
align 8
idt:
    times 12 dq 0
    GATE ss_handler, 0x8e
    GATE gp_handler, 0x8e
    times (0x21 - 14) dq 0
    GATE pass_handler, 0xee
    GATE fail_handler, 0xee
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    dd 0, R0_STACK, SEL_DATA0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 104
