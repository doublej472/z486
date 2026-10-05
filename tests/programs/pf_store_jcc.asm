; pf_store_jcc - a store #PF reported after a younger Jcc has already issued
; (Windows 95 KERNEL32: "mov dword [eax],0A0000000h / jne +37h" on a fresh
; not-present page).  The fault delivery runs while `i` still holds the Jcc, so
; its rel_branch_kind leaks a displacement into the delivery's IND address and
; the IDT gate read goes to the wrong place; the handler is then never reached.
; The handler maps the page and IRETs, the store retries and completes, and the
; jump must then go the expected way.  A store with a non-branch successor is
; the control.  The fault page's PTE is at 0x2004 (PDE 0x80's PT at 0x2000).
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
DATA_BASE   equ 0x20000000
FAULT_OFF   equ 0x00001000
FAULT_PTE   equ 0x00002004            ; PTE for DATA_BASE+FAULT_OFF
FAULT_PHYS  equ 0x00021000

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 0x08: code, base 0x00010000
    dq 0x20cf93000000ffff     ; 0x10: data, base 0x20000000
    dq 0x30cf93000000ffff     ; 0x18: stack, base 0x30000000
    dq 0x00cf93000000ffff     ; 0x20: flat data, base 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

pf_handler:
    add esp, 4                          ; discard #PF error code
    mov dword [es:FAULT_PTE], FAULT_PHYS | 0x23
    invlpg [FAULT_OFF]                  ; DS base -> linear DATA_BASE+FAULT_OFF
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
    mov ax, 0x20
    mov es, ax
    mov esp, 0x8000
    mov eax, 0x12345678
    mov edx, FAULT_OFF

    ; control: store #PF, successor is a MOV (no branch kind)
    and dword [es:FAULT_PTE], 0xfffffffe
    invlpg [FAULT_OFF]
    mov esi, 7
fault_store0:
    mov [edx], eax
    mov ecx, 0
    cmp esi, 7
    jne fail

    ; case 1: Jcc taken (ZF=1), short form
    and dword [es:FAULT_PTE], 0xfffffffe
    invlpg [FAULT_OFF]
    mov esi, 0
    pushfd
    or dword [esp], 40h
    popfd
fault_store1:
    mov [edx], eax
    jz .t1_taken
    jmp .t1_join
.t1_taken:
    mov esi, 1
.t1_join:
    cmp esi, 1
    jne fail

    ; case 2: Jcc not taken (ZF=0), near form (Win95 distance)
    and dword [es:FAULT_PTE], 0xfffffffe
    invlpg [FAULT_OFF]
    mov esi, 0
    pushfd
    and dword [esp], ~40h
    popfd
fault_store2:
    mov [edx], eax
    jz near .t2_taken
    jmp .t2_join
    times 37h nop
.t2_taken:
    mov esi, 1
.t2_join:
    cmp esi, 0
    jne fail

    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
