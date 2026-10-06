; vipt_rmw_fault_rf: copy of vipt_rmw_fault that also requires RF=1 in the pushed EFLAGS
; A crossing memory-destination ALU operation must reject RD_FAST and take the
; original restartable routine.  A fault on the second page changes neither
; the first-page bytes, source register, nor saved flags.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_BASE   equ 0x20000000
FAULT_EA    equ 0x00000ffe

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 0x08: code, base 0x00010000
    dq 0x20cf93000000ffff     ; 0x10: data, base 0x20000000
    dq 0x30cf93000000ffff     ; 0x18: stack, base 0x30000000
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

pf_handler:
    test dword [ss:esp + 12], 0x10000   ; RF=1 in the fault frame (486 PRM 11.3.1.1)
    jz fail_handler
    mov ebx, cr2
    cmp ebx, DATA_BASE + 0x1000
    jne fail_handler
    test dword [ss:esp], 1            ; second page must be not-present
    jnz fail_handler
    cmp dword [ss:esp + 4], fault_rmw
    jne fail_handler
    cmp eax, 1
    jne fail_handler
    test dword [ss:esp + 12], 1       ; input CF remains in fault frame
    jz fail_handler
    mov dword [ss:esp + 4], after_fault
    add esp, 4                        ; discard page-fault error code
    iretd

fail_handler:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 8
idt:
    times 14 dq 0
    dw pf_handler
    dw 0x0008
    db 0
    db 0x8e
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd 0x00010000 + idt

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov word [FAULT_EA], 0xbeef
    times 32 nop
    mov bx, [FAULT_EA]
    times 8 nop

    mov eax, 1
    mov esp, 0x0f00
    stc
fault_rmw:
    add dword [FAULT_EA], eax
after_fault:
    cmp eax, 1
    jne fail
    cmp word [FAULT_EA], 0xbeef
    jne fail

    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
