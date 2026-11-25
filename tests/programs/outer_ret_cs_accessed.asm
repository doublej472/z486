; outer_ret_cs_accessed.asm - the Accessed bit of an outer-level return's CS
; descriptor is set only by a return that completes
;
; i486 PRM, RET and IRET, "return to outer privilege level": the return CS
; and its descriptor are examined, then the return SS selector and its
; descriptor (null -> #GP(0); RPL, type or DPL -> #GP(selector); not present
; -> #SS/#NP(selector)), and only after every check "Load the CS register
; with the return CS descriptor; Load the SS register with the return SS
; descriptor".  PRM 5.1.3.1 (Type field): the Accessed bit is set "if the
; segment is accessed"; 5.3 (MOV to a segment register): loading a segment
; register sets the Accessed bit, the Intel486 only if it is not already set.
; A return whose SS check faults loads no segment register, so it leaves the
; Accessed bit of the return CS descriptor (and of the SS descriptor) as it
; was.  A return that completes sets both.
;
; Each form (o32 RETF, o16 RETF, o32 RETF imm16, o16 RETF imm16, IRETD,
; o16 IRET) runs:
;   - with the ring-3 CS descriptor's A clear and a faulting SS (null,
;     RPL != CS RPL, DPL 2, not present) and a not-present CS: afterwards the
;     A bits of the CS and SS descriptors are still clear;
;   - completing returns with every combination of CS / SS A bits, and with
;     CS or SS in the LDT (LDT index = a GDT index of the other kind, so a
;     write through the wrong table is seen): afterwards both A bits are set
;     and the same-index descriptor of the other table is untouched.
; A same-level RETF / IRETD (to a ring-0 code descriptor whose A is clear)
; sets that A bit as before.
; Ring 3 comes back through a DPL 3 interrupt gate (vector 0x40).
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code:
; (case << 8) | check.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18    ; DPL 3 code
SEL_DATA3   equ 0x20    ; DPL 3 writable data
SEL_TSS     equ 0x28
SEL_CODE3NP equ 0x30    ; DPL 3 code, not present
SEL_DATA3NP equ 0x38    ; DPL 3 writable data, not present
SEL_DATA2   equ 0x40    ; DPL 2 writable data
SEL_LDT     equ 0x48
SEL_CODE0B  equ 0x50    ; second DPL 0 code
; LDT selectors (TI = 1): index 3 is code (GDT index 3 is code too),
; index 4 is data (GDT index 4 is data).
SEL_LCODE3  equ 0x1C
SEL_LDATA3  equ 0x24

STACK0_TOP  equ 0xE000
TSS_ESP0    equ 0xD000
STACK3_TOP  equ 0xF000

; Access-byte addresses (offsets in the DS = SEL_DATA0 segment, base 0x10000)
A_CODE3     equ gdt + SEL_CODE3 + 5
A_DATA3     equ gdt + SEL_DATA3 + 5
A_CODE3NP   equ gdt + SEL_CODE3NP + 5
A_DATA3NP   equ gdt + SEL_DATA3NP + 5
A_DATA2     equ gdt + SEL_DATA2 + 5
A_LCODE3    equ ldt + (SEL_LCODE3 & ~7) + 5
A_LDATA3    equ ldt + (SEL_LDATA3 & ~7) + 5
A_CODE0B    equ gdt + SEL_CODE0B + 5

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm_entry

BITS 32
pm_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax
    mov ax, SEL_LDT
    lldt ax
    jmp cases

; Push a return frame.  %1 form, %2 SS, %3 CS, %4 EIP
; Forms: 0 o32 RETF, 1 o16 RETF, 2 o32 RETF 8, 3 o16 RETF 4, 4 IRETD, 5 o16 IRET
%macro FRAME 4
%if %1 == 0
    push dword %2
    push dword STACK3_TOP
    push dword %3
    push dword %4
%elif %1 == 1
    push word %2
    push word STACK3_TOP
    push word %3
    push word %4
%elif %1 == 2
    push dword %2
    push dword STACK3_TOP
    push dword 0x11111111
    push dword 0x22222222
    push dword %3
    push dword %4
%elif %1 == 3
    push word %2
    push word STACK3_TOP
    push word 0x3333
    push word 0x4444
    push word %3
    push word %4
%elif %1 == 4
    push dword %2
    push dword STACK3_TOP
    push dword 0x00000002
    push dword %3
    push dword %4
%else
    push word %2
    push word STACK3_TOP
    push word 0x0002
    push word %3
    push word %4
%endif
%endmacro

%macro RET_INSN 1
%if %1 == 0
    retf
%elif %1 == 1
    o16 retf
%elif %1 == 2
    retf 8
%elif %1 == 3
    o16 retf 4
%elif %1 == 4
    iretd
%else
    o16 iret
%endif
%endmacro

; A bit of the access byte at %1: %2 = 0 clear it, 1 set it
%macro SETA 2
%if %2
    or byte [%1], 1
%else
    and byte [%1], 0xFE
%endif
%endmacro

; Check the A bit at %1 is %2, else fail with check %3
%macro CHKA 3
    mov bl, %3
    mov al, [%1]
    and al, 1
    cmp al, %2
    jne fail
%endmacro

; A faulting return.  %1 id, %2 form, %3 SS, %4 CS, %5 vector,
; %6 the SS descriptor's access byte, %7 the CS descriptor's access byte
%macro FCASE 7
    mov esp, STACK0_TOP
    mov dword [case_id], %1
    mov dword [exp_vec], %5
    mov dword [resume], %%next
    mov dword [got_vec], 0
    SETA %6, 0
    SETA %7, 0
    FRAME %2, %3, %4, ring3_land
    RET_INSN %2
%%next:
    mov ebx, (%1 << 8) | 0x10
    cmp dword [got_vec], %5
    jne fail
    CHKA %7, 0, 0x11            ; return CS descriptor: A still clear
    CHKA %6, 0, 0x12            ; return SS descriptor: A still clear
%endmacro

; A completing return.  %1 id, %2 form, %3 SS, %4 CS,
; %5 / %6 the SS / CS access byte and its A before the return,
; %7 / %8 the same-index access bytes of the other table (A clear, kept clear)
%macro OKCASE 8
    mov esp, STACK0_TOP
    mov dword [case_id], %1
    mov dword [resume], %%next
    mov dword [got_vec], 0
    SETA %5, 0
    SETA %6, 0
    SETA %7, 0
    SETA %8, 0
    FRAME %2, %3, %4, ring3_back
    RET_INSN %2
%%next:
    mov ebx, (%1 << 8) | 0x20
    cmp dword [got_vec], 0x40   ; came back from ring 3
    jne fail
    CHKA %6, 1, 0x21            ; return CS descriptor: A set
    CHKA %5, 1, 0x22            ; return SS descriptor: A set
    CHKA %7, 0, 0x23            ; the other table's same-index entries
    CHKA %8, 0, 0x24            ; are untouched
%endmacro

; As OKCASE with one of the two A bits preset.  %1 id, %2 form, %3 SS,
; %4 CS, %5 SS access byte, %6 CS access byte, %7 SS A before, %8 CS A before
%macro MIXCASE 8
    mov esp, STACK0_TOP
    mov dword [case_id], %1
    mov dword [resume], %%next
    mov dword [got_vec], 0
    SETA %5, %7
    SETA %6, %8
    FRAME %2, %3, %4, ring3_back
    RET_INSN %2
%%next:
    mov ebx, (%1 << 8) | 0x30
    cmp dword [got_vec], 0x40
    jne fail
    CHKA %6, 1, 0x31
    CHKA %5, 1, 0x32
%endmacro

; Every case for one form.  %1 form.
%macro RFORM 1
    FCASE  (%1*16+0), %1, 0,                 SEL_CODE3 | 3,   13, A_DATA3,   A_CODE3
    FCASE  (%1*16+1), %1, SEL_DATA0,         SEL_CODE3 | 3,   13, A_DATA3,   A_CODE3
    FCASE  (%1*16+2), %1, SEL_DATA2 | 3,     SEL_CODE3 | 3,   13, A_DATA2,   A_CODE3
    FCASE  (%1*16+3), %1, SEL_DATA3NP | 3,   SEL_CODE3 | 3,   12, A_DATA3NP, A_CODE3
    FCASE  (%1*16+4), %1, SEL_DATA3 | 3,     SEL_CODE3NP | 3, 11, A_DATA3,   A_CODE3NP
    FCASE  (%1*16+5), %1, 0,                 SEL_LCODE3 | 3,  13, A_DATA3,   A_LCODE3
    OKCASE (%1*16+6), %1, SEL_DATA3 | 3,     SEL_CODE3 | 3,   A_DATA3, A_CODE3, A_LDATA3, A_LCODE3
    OKCASE (%1*16+7), %1, SEL_DATA3 | 3,     SEL_LCODE3 | 3,  A_DATA3, A_LCODE3, A_LDATA3, A_CODE3
    OKCASE (%1*16+8), %1, SEL_LDATA3 | 3,    SEL_CODE3 | 3,   A_LDATA3, A_CODE3, A_DATA3, A_LCODE3
    OKCASE (%1*16+9), %1, SEL_LDATA3 | 3,    SEL_LCODE3 | 3,  A_LDATA3, A_LCODE3, A_DATA3, A_CODE3
    MIXCASE (%1*16+10), %1, SEL_DATA3 | 3,   SEL_CODE3 | 3,   A_DATA3, A_CODE3, 1, 0
    MIXCASE (%1*16+11), %1, SEL_DATA3 | 3,   SEL_CODE3 | 3,   A_DATA3, A_CODE3, 0, 1
    MIXCASE (%1*16+12), %1, SEL_LDATA3 | 3,  SEL_LCODE3 | 3,  A_LDATA3, A_LCODE3, 1, 0
%endmacro

cases:
    RFORM 0
    RFORM 1
    RFORM 2
    RFORM 3
    RFORM 4
    RFORM 5
    ; same-level returns: %1 id, %2 form (0 RETF, 4 IRETD)
%macro SAMECASE 2
    mov esp, STACK0_TOP
    mov dword [case_id], %1
    SETA A_CODE0B, 0
%if %2 == 0
    push dword SEL_CODE0B
    push dword %%back
    retf
%else
    pushfd
    push dword SEL_CODE0B
    push dword %%back
    iretd
%endif
%%back:
    mov ebx, (%1 << 8) | 0x40
    mov ax, cs
    cmp ax, SEL_CODE0B
    jne fail
    CHKA A_CODE0B, 1, 0x41
    push dword SEL_CODE0
    push dword %%home
    retf
%%home:
%endmacro
    SAMECASE 0xE0, 0
    SAMECASE 0xE1, 4
    mov dx, STATUS_PORT
    mov al, STATUS_PASS
    out dx, al
    hlt
    jmp $

; Ring 3: a faulting case must never get here.
ring3_land:
    int 0x41

; Ring 3 after a completing return: back to ring 0.
ring3_back:
    int 0x40

; Ring 0 failure report
fail:
    mov eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp fail

; ---------------------------------------------------------------------------
; Handlers (32-bit interrupt gates to SEL_CODE0).
isr_np:
    mov dword [ss:got_vec], 11
    jmp isr_fault
isr_ss:
    mov dword [ss:got_vec], 12
    jmp isr_fault
isr_gp:
    mov dword [ss:got_vec], 13
isr_fault:
    mov ebx, [ss:case_id]
    shl ebx, 8
    mov bl, 1
    mov eax, [ss:got_vec]
    cmp eax, [ss:exp_vec]
    jne fail
    mov bl, 2                   ; delivered at CPL 0 (frame CS)
    movzx eax, word [esp + 8]
    cmp eax, SEL_CODE0
    jne fail
    mov eax, [ss:resume]
    mov [esp + 4], eax
    add esp, 4
    iretd

; DPL 3 gate from ring 3: a completing return reached ring 3
isr_back:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ebx, [case_id]
    shl ebx, 8
    mov bl, 3                   ; entered from ring 3 (frame CS, SS)
    movzx eax, word [esp + 4]
    cmp eax, SEL_CODE3 | 3
    je .cs_ok
    cmp eax, SEL_LCODE3 | 3
    jne fail
.cs_ok:
    mov dword [got_vec], 0x40
    mov esp, STACK0_TOP
    jmp dword [resume]

; DPL 3 gate from ring 3 after a faulting case: fail
isr_land:
    mov ax, SEL_DATA0
    mov ds, ax
    mov ebx, [case_id]
    shl ebx, 8
    or ebx, 0xAA
    jmp fail

isr_other:
    mov ebx, [ss:case_id]
    shl ebx, 8
    or ebx, 0xEF
    jmp fail

;==================================================================
align 4
case_id: dd 0
exp_vec: dd 0
resume:  dd 0
got_vec: dd 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x00CFFA010000FFFF       ; 0x18 code3 (readable)
    dq 0x00CFF2010000FFFF       ; 0x20 data3
    dw 0x0067                   ; 0x28 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CF7A010000FFFF       ; 0x30 code3, not present
    dq 0x00CF72010000FFFF       ; 0x38 data3, not present
    dq 0x00CFD2010000FFFF       ; 0x40 data DPL 2
    dw ldt_end - ldt - 1        ; 0x48 LDT
    dw ldt
    db 0x01
    db 0x82
    db 0x00
    db 0x00
    dq 0x00CF9A010000FFFF       ; 0x50 code0 (A clear)
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
ldt:
    dq 0
    dq 0
    dq 0
    dq 0x00CFFA010000FFFF       ; LDT 0x1C code3
    dq 0x00CFF2010000FFFF       ; LDT 0x24 data3
ldt_end:

%macro IGATE 2
    dw %1
    dw SEL_CODE0
    db 0
    db %2
    dw 0
%endmacro

align 8
idt:
%rep 11
    IGATE isr_other, 0x8E
%endrep
    IGATE isr_np, 0x8E          ; 11
    IGATE isr_ss, 0x8E          ; 12
    IGATE isr_gp, 0x8E          ; 13
%rep 50
    IGATE isr_other, 0x8E
%endrep
    IGATE isr_back, 0xEE        ; 0x40, DPL 3
    IGATE isr_land, 0xEE        ; 0x41, DPL 3
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss386:
    dd 0
    dd TSS_ESP0
    dd SEL_DATA0
    times 22 dd 0
    dw 0
    dw 104
