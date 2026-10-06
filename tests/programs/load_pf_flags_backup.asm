; A load can issue in its predecessor's last ALU cycle, before that ALU's
; flags commit. If the load page-faults, the fault restores EFLAGS from the
; backup taken at the load's issue, which must include the ALU's flags.

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

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x38000
    mov ebp, DATA
    mov edx, 0xfd94b889
    mov edi, 0x0ddf28fa
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    mov ecx, 8
.settle:                                ; let the PTE store and refetch drain
    dec ecx
    jnz .settle
    mov ebx, 1
    or ebx, ebx                         ; PF=0, ZF=0, SF=0

    and edx, edi                        ; 0x0d942888: PF=1, ZF=0, SF=0
    mov edi, [ebp + 0x99]               ; #PF, restarted after the handler
    pushfd
    pop eax

    and eax, 0x8D5
    cmp eax, 0x004                      ; PF only
    jne fail
    cmp edx, 0x0d942888
    jne fail
    cmp dword [CODE_BASE + pf_count], 1
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
