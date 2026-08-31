; REP STOS must expose only completed elements at a page-fault boundary.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_BASE   equ 0x20000000
LAST_DWORD equ 0x00000ffc
FAULT_OFF  equ 0x00001000

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

pf_handler:
    mov ebx, cr2
    cmp ebx, DATA_BASE + FAULT_OFF
    jne fail_handler
    cmp dword [ss:esp], 0x2
    jne fail_handler
    cmp dword [ss:esp + 4], fault_rep
    jne fail_handler
    cmp ecx, 1
    jne fail_handler
    cmp edi, FAULT_OFF
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
    cld
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x8000
    mov eax, 0x12345678
    mov edi, LAST_DWORD
    mov ecx, 2

fault_rep:
    rep stosd

after_fault:
    cmp dword [LAST_DWORD], 0x12345678
    jne fail
    cmp ecx, 1
    jne fail
    cmp edi, FAULT_OFF
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
