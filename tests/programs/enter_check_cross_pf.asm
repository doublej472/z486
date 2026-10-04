; enter_check_cross_pf.asm - ENTER's crossing stack check must validate BOTH
; pages; a not-present/read-only second page must #PF before ESP moves.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

CODE_LINEAR  equ 0x00010000
PRIME_ADDR   equ 0x00001FFC     ; dword fully inside present page 0x1000
MISSING_PAGE equ 0x00002000     ; second page of the crossing probe: absent
STACK_TOP    equ 0x00003024     ; EBP push -> 0x3020; #PF frame stays in page 0x3000
ENTER_IMM16  equ 0x1023         ; final ESP = 0x3020 - 0x1023 = 0x1FFD
DIAG_CR2     equ 0x00003000
DIAG_ERR     equ 0x00003004

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff    ; 0x08: code, base 0x00010000, limit 0xFFFFF
    dq 0x00cf93000000ffff    ; 0x10: data, base 0x00000000, limit 0xFFFFF
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_LINEAR + gdt

pf_handler:
    mov dword [DIAG_ERR], 0
    mov eax, [ss:esp]           ; #PF pushes an error code on top
    mov [DIAG_ERR], eax
    mov eax, cr2
    mov [DIAG_CR2], eax

    and eax, 0xFFFFF000
    cmp eax, MISSING_PAGE
    jne pf_bad

    mov eax, cr2
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

pf_bad:
    mov eax, cr2
    or eax, 0x80000000
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
idt:
    times 14 dq 0           ; vectors 0..13 absent
    dw pf_handler           ; vector 14: #PF
    dw 0x0008
    db 0
    db 0x8e                 ; present DPL0 386 interrupt gate
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_LINEAR + idt

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov esp, STACK_TOP
    mov ebp, 0x11223344

    ; Prime the probe's first page: present + dirty in the D-cache/TLB, so
    ; HEAD's crossing check takes the fast (no second lookup) route.
    mov dword [PRIME_ADDR], 0x55667788
    mov eax, [PRIME_ADDR]
    cmp eax, 0x55667788
    jne fail_setup

enter_probe:
    enter ENTER_IMM16, 0

    ; Reaching here means no #PF was delivered for the absent second page.
    jmp fail_no_fault

fail_setup:
    mov eax, 2
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_no_fault:
    mov eax, 1
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

times 0x1000 - ($ - $$) db 0
