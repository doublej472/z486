; call_gate16_params.asm - 16-bit call gate with word parameters, ring 3 -> ring 0
;
; Variant of call_gate16_ldt: both gates copy 2 words of parameters to the
; inner stack (16-bit gate: word-sized), the routine checks them and
; returns with RETF 4, which drops them from both stacks.
;
; Original description:
;
; Win95 Setup's SYSDETMG.DLL makes a ring-0 alias of a code segment and a
; 16-bit call gate to it in the LDT (access byte 0xE4, the target selector
; as AllocSelector returned it: TI=1, RPL=3), then calls the gate with
; CALL FAR [BP-4] from 16-bit ring-3 code at IOPL 0. The gate target's RPL
; is ignored (CPL becomes the target's DPL). The ring-0 routine runs CLI,
; PUSH EBP, IN, and returns with a 16-bit RETF to ring 3.
;
; Two gates: target selector RPL 3 (as SYSDETMG) and RPL 0. Each call must
; arrive at CPL 0 (CS = 0x04), on the TSS stack, and return to ring 3 with
; SS:SP restored. Any fault fails with its vector, EIP and error code; the
; test ends with a HLT at CPL 3, whose #GP passes once both calls ran.
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
SEL_CODE3   equ 0x18    ; 16-bit code, DPL 3
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_LDT     equ 0x30

LSEL_CODE0A equ 0x04    ; LDT 0: ring-0 16-bit alias of the code
LSEL_GATE3  equ 0x0F    ; LDT 1: gate, target selector RPL 3
LSEL_GATE0  equ 0x17    ; LDT 2: gate, target selector RPL 0

SEL_CODE3_RPL3 equ (SEL_CODE3 | 3)
SEL_DATA3_RPL3 equ (SEL_DATA3 | 3)

STACK0_TOP  equ 0x3000
STACK3_TOP  equ 0x4000

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

    ; IRET outer-level to 16-bit ring 3 with IOPL=0
    push dword SEL_DATA3_RPL3   ; SS3
    push dword STACK3_TOP       ; ESP3
    push dword 0x00000002       ; EFLAGS IOPL=0, IF=0
    push dword SEL_CODE3_RPL3
    push dword ring3_entry
    iretd

BITS 16
ring3_entry:
    mov ax, SEL_DATA3_RPL3
    mov ds, ax
    mov bp, sp
    sub sp, 8
    mov word [bp-4], 0
    mov word [bp-2], LSEL_GATE3

    mov word [stage], 1
    mov word [seen_cs], 0
    cli                         ; faults at IOPL 0: the handler skips it
    push word 0x1111
    push word 0x2222
    call far [bp-4]
    cmp sp, STACK3_TOP - 8
    jne r3_fail_sp
    mov ax, ss
    cmp ax, SEL_DATA3_RPL3
    jne r3_fail_sp
    cmp word [seen_cs], LSEL_CODE0A
    jne r3_fail_cs

    mov word [bp-2], LSEL_GATE0
    mov word [stage], 2
    mov word [seen_cs], 0
    push word 0x1111
    push word 0x2222
    call far [bp-4]
    cmp sp, STACK3_TOP - 8
    jne r3_fail_sp
    cmp word [seen_cs], LSEL_CODE0A
    jne r3_fail_cs

    mov word [stage], 3
done_site:
    hlt                         ; #GP at CPL 3: the handler passes
    jmp $

r3_fail_sp:
    mov word [stage], 0x31
    hlt
r3_fail_cs:
    mov word [stage], 0x32
    hlt

; Ring-0 routine, reached through the gates (as SYSDETMG's keyboard probe)
gate16_target:
    cli
    push ebp
    mov ebp, esp
    mov ax, cs
    mov [seen_cs], ax
    ; inner stack: [SP+0] EBP (4), +4 IP, +6 CS, +8 param 0x2222,
    ; +10 param 0x1111, +12 SP, +14 SS
    cmp sp, STACK0_TOP - 12 - 4
    jne .bad_stack
    cmp word [esp+8], 0x2222
    jne .bad_stack
    cmp word [esp+10], 0x1111
    jne .bad_stack
    cmp word [esp+12], STACK3_TOP - 12
    jne .bad_stack
    in al, 0x21
    pop ebp
    retf 4
.bad_stack:
    mov word [seen_cs], 0xBAD
    pop ebp
    retf 4

;------------------------------------------------------------------
; Ring 0 fault handlers (DPL0 386 interrupt gates)
;------------------------------------------------------------------
BITS 32
%macro FAULT_ERR 1
isr_%1:
    push dword %1
    jmp fault_common
%endmacro
FAULT_ERR 0x0A
FAULT_ERR 0x0B
FAULT_ERR 0x0C

isr_gp:
    ; frame after the pushes: [esp]=DS, +4 EAX, +8 err, +12 EIP, +16 CS
    push eax
    push ds
    mov ax, SEL_DATA0
    mov ds, ax
    movzx eax, word [esp+16]    ; CS
    cmp ax, SEL_CODE3_RPL3
    jne .other
    mov eax, [esp+12]           ; EIP
    cmp word [stage], 3
    jne .not_done
    cmp eax, done_site
    jne .other
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
.not_done:
    ; the CLI before the first call: skip it
    movzx eax, word [esp+12]
    cmp byte [eax], 0xFA        ; DS and the code share base 0x10000
    jne .other
    inc dword [esp+12]
    pop ds
    pop eax
    add esp, 4
    iretd
.other:
    pop ds
    pop eax
    push dword 0x0D
    ; fall through

fault_common:
    ; [esp]=vector, +4 err, +8 EIP
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, [esp+8]            ; EIP
    shl eax, 16
    mov al, [esp]               ; vector
    mov ah, [stage]
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [esp+4]            ; error code
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

;==================================================================
; Data
;==================================================================
align 4
stage:
    dw 0
seen_cs:
    dw 0

align 8
gdt:
    dq 0x0000000000000000
    ; 0x08: ring0 32-bit code, base 0x10000
    dq 0x00CF9B010000FFFF
    ; 0x10: ring0 32-bit data, base 0x10000
    dq 0x00CF93010000FFFF
    ; 0x18: ring3 16-bit code, base 0x10000, limit 0xFFFF
    dq 0x0000FB010000FFFF
    ; 0x20: ring3 data, base 0x10000 (DPL=3)
    dq 0x00CFF3010000FFFF
    ; 0x28: available 386 TSS (type 9), base = tss386+0x10000, limit 0x67
    dw 0x0067
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    ; 0x30: LDT, base = ldt+0x10000
    dw ldt_end - ldt - 1
    dw ldt
    db 0x01
    db 0x82
    db 0x00
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
ldt:
    ; 0x04: ring-0 16-bit code alias, base 0x10000, limit 0xFFFF
    dq 0x00009B010000FFFF
    ; 0x0C: 16-bit call gate, DPL 3, target LDT 0 with RPL 3 (as SYSDETMG)
    dw gate16_target
    dw LSEL_CODE0A | 3
    db 2
    db 0xE4
    dw 0
    ; 0x14: the same gate, target RPL 0
    dw gate16_target
    dw LSEL_CODE0A
    db 2
    db 0xE4
    dw 0
ldt_end:

%macro IGATE 1
    dw %1
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
    times 0x0A dq 0
    IGATE isr_0x0A
    IGATE isr_0x0B
    IGATE isr_0x0C
    IGATE isr_gp
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

; 386 TSS: ESP0 at +4, SS0 at +8, no I/O bitmap
align 4
tss386:
    dd 0
    dd STACK0_TOP               ; +4  ESP0
    dd SEL_DATA0                ; +8  SS0
    times 22 dd 0
    dw 0
    dw 104                      ; +0x66: I/O map base past the limit
tss386_end:
