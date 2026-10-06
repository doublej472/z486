; A store that misses the direct store route posts through paging while its
; successor issues into the dead slot and waits behind the write. When the
; store faults on a not-present page, the successor's word must not execute in
; the fault cycle: here a LEA that overwrites the store's source register,
; which the restarted store would then write.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
CODE_BASE   equ 0x00010000
DATA        equ 0x00020000
DATA_PTE    equ 0x00001000 + (DATA >> 12) * 4
VAL1        equ 0x11223344
VAL2        equ 0x55667788

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
    push eax
    inc dword [CODE_BASE + pf_count]
    cmp dword [CODE_BASE + pf_count], 1
    jne .map
    mov eax, cr2
    mov [CODE_BASE + pf_cr2], eax
    mov eax, [esp + 8]                  ; faulting EIP
    mov [CODE_BASE + pf_eip], eax
.map:
    or dword [DATA_PTE], 1
    pop eax
    add esp, 4                          ; discard #PF error code
    iretd

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
    dd CODE_BASE + idt

align 4
pf_count: dd 0
pf_cr2:   dd 0
pf_eip:   dd 0

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x38000
    mov esi, VAL1
    mov ebp, DATA
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]

store1:
    mov [ebp + 0x10], esi
    lea esi, [ebp + 0xac]
    mov ecx, 8
.settle:
    dec ecx
    jnz .settle

    cmp dword [DATA + 0x10], VAL1
    jne fail
    cmp esi, DATA + 0xac
    jne fail
    cmp dword [CODE_BASE + pf_count], 1
    jne fail
    cmp dword [CODE_BASE + pf_cr2], DATA + 0x10
    jne fail
    cmp dword [CODE_BASE + pf_eip], store1
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
