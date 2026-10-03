; A direct VIPT A1 load must preserve a precise #GP when the direct offset is
; beyond the data-segment limit, without committing its speculative data.

BITS 32
org 0

STATUS_PORT equ 0xE0
FAULT_OFF   equ 0x00001000
SENTINEL    equ 0x51A7CF02

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x20cf93000000ffff
    dq 0x30cf93000000ffff
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

gp_handler:
    cmp dword [ss:esp], 0
    jne fail_handler
    cmp dword [ss:esp + 4], fault_load
    jne fail_handler
    cmp eax, SENTINEL
    jne fail_handler
    mov dword [ss:esp + 4], after_fault
    add esp, 4
    iretd

fail_handler:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 8
idt:
    times 13 dq 0
    dw gp_handler
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
    mov esp, 0x8000
    mov eax, SENTINEL

fault_load:
    mov eax, [FAULT_OFF]

after_fault:
    cmp eax, SENTINEL
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
