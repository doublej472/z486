; A posted store that faults on a not-present page, followed by a Jcc with a
; nonzero displacement. The write fault is delivered while the Jcc is the
; current instruction; the delivery microcode's IDT address (IND = vector*8
; + 4) must not take the Jcc's held displacement. Windows 95 hung in a #GP
; delivery loop here (KERNEL32: mov dword [eax], imm32 / jnz).

BITS 32
ORG 0

STATUS_PORT equ 0xE0
CODE_BASE   equ 0x00010000
DATA        equ 0x00020000
DATA_PTE    equ 0x00001000 + (DATA >> 12) * 4

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 0x08: code, base 0x00010000
    dq 0x00cf93000000ffff     ; 0x10: data, base 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_BASE + gdt

pf_handler:
    inc dword [CODE_BASE + pf_count]
    or dword [DATA_PTE], 1
    add esp, 4                          ; discard #PF error code
    iretd

gp_handler:
    mov al, 0xee
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
    dw pf_handler
    dw 0x0008
    db 0
    db 0x8e
    dw 0
    times 8 dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_BASE + idt

align 4
pf_count: dd 0
taken:    dd 0

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x38000
    mov eax, DATA
    mov ecx, 4                          ; later passes run from the cache

.pass:
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    test ecx, 1                         ; ZF alternates: jnz taken / not taken
    mov dword [eax], 0x12345678
    jnz .far
    mov dword [eax + 4], ecx
.back:
    dec ecx
    jnz .pass
    jmp .check

    times 0x30 db 0x90
.far:
    inc dword [CODE_BASE + taken]
    jmp .back

.check:
    cmp dword [CODE_BASE + pf_count], 4
    jne fail
    cmp dword [CODE_BASE + taken], 2
    jne fail
    cmp dword [DATA], 0x12345678
    jne fail
    cmp dword [DATA + 4], 2
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
