; cs_limit_xfer_priv.asm - privilege-changing transfers to an offset beyond the CS limit
;
; i486 Programmer's Reference Manual: the new instruction pointer is checked
; against the code segment limit as a step of the transfer, before it
; completes: CALL through a call gate to a more privileged level, "EIP must
; be in code segment limit ELSE #GP(0)" ahead of "Load new SS:eSP value from
; TSS" (CALL operation, p. 26-47); RET and IRET to an outer level,
; "Instruction pointer must be within code segment limit ELSE #GP(0)" (IRET
; operation, p. 26-176); INT n, "Instruction pointer must be in CS limit,
; else #GP(0)" (p. 26-169).  The #GP is the transfer's fault: the frame
; names it at its own privilege level and the registers are as before it
; (9.1, p. 9-2; 9.2, p. 9-3), so no stack switch, CPL change or push is left
; behind.  9.9.13 (p. 9-21): no descriptor caused it, so the error code is 0.
;
; Ring 0 #GP handler (interrupt gate to the flat ring-0 code).  Cases:
;   1  ring 3: INT 42h through a DPL3 interrupt gate to 18h:3000h (ring 0,
;      limit 1FF7h)
;   2  ring 3: far CALL through a DPL3 call gate to 18h:3000h
;   3  ring 0: RETF to ring 3, 33h:3000h (ring 3, limit 1FF7h)
;   4  ring 0: IRETD to ring 3, 33h:3000h
;   5  ring 3 inside 33h: JMP rel32 to 3000h
;   6  ring 3 inside 33h: CALL rel32 to 3000h
;   7  ring 3 inside 33h: CALL EAX (EAX = 3000h)
;
; Checks (port 0xE4 = (case << 8) | check): 1 exactly one #GP, 2 error code
; low word 0, 3 frame EIP = the transfer, 4 frame CS = the transfer's CS,
; 5 the transfer's ESP (from the ring-3 frame, or the ring-0 ESP before the
; fault for a same-level frame), 6 EBX (the target ran), 7 the ring-3 SS in
; the frame, 8 the handler's stack is the ring-0 SS (the ring-3 stack
; segment 4Bh has a different base, so a stale SS descriptor shows).

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_LIM0    equ 0x18    ; code32 DPL0, limit 1FF7h
SEL_CODE3   equ 0x23    ; code32 DPL3, flat
SEL_DATA3   equ 0x2B    ; data32 DPL3, flat
SEL_LIM3    equ 0x33    ; code32 DPL3, limit 1FF7h
SEL_TSS     equ 0x38
SEL_GATE    equ 0x43    ; call gate DPL3 -> 18h:3000h
SEL_STK3    equ 0x4B    ; data32 DPL3, base 20000h: the ring-3 stack

BEYOND      equ 0x3000
STACK0      equ 0x6000
STACK3      equ 0x7000  ; in SEL_STK3 (linear 27000h)
LEVEL3      equ 1       ; case flag: the frame is a ring-3 frame

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
    mov esp, STACK0
    mov ax, SEL_TSS
    ltr ax
    jmp cases

; %1 case, %2 expected frame CS, %3 LEVEL3 or 0
%macro XBEGIN 3
    mov dword [case_id], %1
    mov dword [exp_cs], %2
    mov dword [level3], %3
    mov dword [resume], %%next
    mov dword [got], 0
    mov dword [got_ec], 0xEEEEEEEE
    mov dword [got_eip], 0xEEEEEEEE
    mov dword [got_cs], 0xEEEEEEEE
    mov dword [got_esp], 0xEEEEEEEE
    mov dword [got_ss], 0xEEEEEEEE
    mov dword [ebx_seen], 0xEEEEEEEE
    mov dword [got_stk0], 0xEEEEEEEE
    mov esp, STACK0
    xor ebx, ebx
    mov eax, BEYOND
%define XNEXT %%next
%endmacro
%macro XAT 0
    mov dword [exp_eip], %%x
    mov [exp_esp], esp
%%x:
%endmacro
%macro XEND 0
XNEXT:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    call check
%undef XNEXT
%endmacro
; Drop to ring 3 at %1:%2 (flat ring-3 stack STACK3, DS/ES ring-3 data).
%macro TO_RING3 2
    push dword SEL_STK3
    push dword STACK3
    push dword 0x00000002
    push dword %1
    push dword %2
    mov cx, SEL_DATA3
    mov ds, cx
    mov es, cx
    iretd
%endmacro

cases:
    XBEGIN 1, SEL_CODE3, LEVEL3
    TO_RING3 SEL_CODE3, r3_int
    XEND

    XBEGIN 2, SEL_CODE3, LEVEL3
    TO_RING3 SEL_CODE3, r3_callgate
    XEND

    XBEGIN 3, SEL_CODE0, 0
    push dword SEL_STK3
    push dword STACK3
    push dword SEL_LIM3
    push dword BEYOND
    XAT
    retf
    XEND

    XBEGIN 4, SEL_CODE0, 0
    push dword SEL_STK3
    push dword STACK3
    push dword 0x00000002
    push dword SEL_LIM3
    push dword BEYOND
    XAT
    iretd
    XEND

    XBEGIN 5, SEL_LIM3, LEVEL3
    TO_RING3 SEL_LIM3, r3_jmp
    XEND

    XBEGIN 6, SEL_LIM3, LEVEL3
    TO_RING3 SEL_LIM3, r3_call
    XEND

    XBEGIN 7, SEL_LIM3, LEVEL3
    TO_RING3 SEL_LIM3, r3_callr
    XEND

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; Ring-3 stubs (flat 23h, or 33h within its limit; same offsets).
r3_int:      XAT
             int 0x42
             jmp $
r3_callgate: XAT
             call SEL_GATE:0
             jmp $
r3_jmp:      XAT
             jmp BEYOND
r3_call:     XAT
             call BEYOND
r3_callr:    XAT
             call eax

check:
    mov edx, [case_id]
    shl edx, 8
    inc edx
    cmp dword [got], 1
    jne fail
    inc edx
    cmp word [got_ec], 0
    jne fail
    inc edx
    mov eax, [exp_eip]
    cmp [got_eip], eax
    jne fail
    inc edx
    mov eax, [exp_cs]
    cmp [got_cs], eax
    jne fail
    inc edx
    mov eax, [exp_esp]
    cmp [got_esp], eax
    jne fail
    inc edx
    cmp dword [ebx_seen], 0
    jne fail
    inc edx
    cmp dword [level3], 0
    je .done
    cmp dword [got_ss], SEL_STK3
    jne fail
.done:
    inc edx
    cmp dword [got_stk0], 1
    jne fail
    ret

fail:
    mov eax, edx
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

; Ring-0 #GP handler.  A ring-3 frame carries ESP and SS; a same-level
; frame's ESP is the handler's ESP above it.
isr_gp:
    mov [ss:ebx_seen], ebx
    mov ax, SEL_DATA0
    mov ds, ax
    ; The handler's SS must be the ring-0 data segment (base 10000h, as DS).
    mov dword [ss:esp - 4], 0x5A5A0001
    cmp dword [esp - 4], 0x5A5A0001
    jne .stk_bad
    mov dword [got_stk0], 1
.stk_bad:
    mov eax, [esp]
    mov [got_ec], eax
    mov eax, [esp + 4]
    mov [got_eip], eax
    movzx eax, word [esp + 8]
    mov [got_cs], eax
    test byte [esp + 8], 3
    jz .same
    mov eax, [esp + 16]
    mov [got_esp], eax
    movzx eax, word [esp + 20]
    mov [got_ss], eax
    jmp .rec
.same:
    lea eax, [esp + 16]
    mov [got_esp], eax
.rec:
    inc dword [got]
    mov esp, STACK0
    jmp [resume]

isr_other:
    mov ax, SEL_DATA0
    mov ds, ax
    mov edx, [case_id]
    shl edx, 8
    or edx, 0xEF
    mov esp, STACK0
    jmp fail

;==================================================================
align 4
case_id:  dd 0
level3:   dd 0
resume:   dd 0
got:      dd 0
got_ec:   dd 0
got_eip:  dd 0
got_cs:   dd 0
got_esp:  dd 0
got_ss:   dd 0
exp_eip:  dd 0
exp_cs:   dd 0
exp_esp:  dd 0
ebx_seen: dd 0
got_stk0: dd 0

align 8
tss:
    dd 0                        ; back link
    dd STACK0                   ; ESP0
    dd SEL_DATA0                ; SS0
    times 104 - 12 db 0
tss_end:

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 08 code32 DPL0, flat
    dq 0x00CF93010000FFFF       ; 10 data32 DPL0, flat
    dq 0x00409B0100001FF7       ; 18 code32 DPL0, limit 1FF7h
    dq 0x00CFFB010000FFFF       ; 20 code32 DPL3, flat
    dq 0x00CFF3010000FFFF       ; 28 data32 DPL3, flat
    dq 0x0040FB0100001FF7       ; 30 code32 DPL3, limit 1FF7h
    dw tss_end - tss - 1        ; 38 32-bit TSS (available)
    dw (tss - $$ + 0x10000) & 0xFFFF
    db ((tss - $$ + 0x10000) >> 16) & 0xFF
    db 0x89
    db 0x00
    db ((tss - $$ + 0x10000) >> 24) & 0xFF
    dw BEYOND & 0xFFFF          ; 40 call gate DPL3 -> 18h:3000h
    dw SEL_LIM0
    db 0
    db 0xEC
    dw BEYOND >> 16
    dq 0x00CFF3020000FFFF       ; 48 data32 DPL3, base 20000h
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro IGATE 3
    dw %1
    dw %2
    db 0
    db %3
    dw 0
%endmacro

align 8
idt:
%rep 13
    IGATE isr_other, SEL_CODE0, 0x8E
%endrep
    IGATE isr_gp, SEL_CODE0, 0x8E      ; 13
%rep 0x42 - 14
    IGATE isr_other, SEL_CODE0, 0x8E
%endrep
    IGATE BEYOND, SEL_LIM0, 0xEE       ; 42h: DPL3 interrupt gate
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

    times BEYOND - ($ - $$) db 0xCC
    mov ebx, 0xBAD
    hlt
