; cr0_486.asm - 486 CR0 write semantics
;
; ET is hardwired to one and the reserved bits read as zero.  CD=1 with NW=1
; and CD=1 alone are legal cache modes; NW=1 with CD=0 is an invalid
; combination that raises #GP(0) without changing CR0, like PG=1 with PE=0.
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 fail code.
BITS 32
ORG 0
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt
align 8
idt:
    times 13 dq 0
    dw gp_handler, 8
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

gp_handler:
    cmp dword [esp], 0          ; error code zero
    jne fail
    cmp [esp+4], esi            ; faulting MOV CR0 restarts
    jne fail
    inc ebp
    mov [esp+4], edi            ; resume past it
    add esp, 4
    iretd

fail:
    mov eax, ecx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt

times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    xor ebp, ebp

    mov ecx, 1                  ; ET stays set, reserved bits read zero
    mov eax, cr0
    and eax, ~0x10
    or eax, 0x1ffaffc0
    mov cr0, eax
    mov eax, cr0
    cmp eax, 0x00000011
    jne fail

    mov ecx, 2                  ; CD=1 NW=1 is legal
    or eax, 0x60000000
    mov cr0, eax
    mov eax, cr0
    cmp eax, 0x60000011
    jne fail
    mov ecx, 3                  ; CD=1 NW=0 is legal
    and eax, ~0x20000000
    mov cr0, eax
    mov eax, cr0
    cmp eax, 0x40000011
    jne fail
    and eax, ~0x40000000
    mov cr0, eax

    mov ecx, 4                  ; NW=1 CD=0 raises #GP(0)
    mov ebx, cr0
    mov eax, ebx
    or eax, 0x20000000
    mov esi, nw_site
    mov edi, nw_done
nw_site:
    mov cr0, eax
nw_done:
    cmp ebp, 1
    jne fail
    mov eax, cr0
    cmp eax, ebx
    jne fail

    mov ecx, 5                  ; PG=1 PE=0 raises #GP(0)
    mov eax, ebx
    and eax, ~1
    or eax, 0x80000000
    mov esi, pg_site
    mov edi, pg_done
pg_site:
    mov cr0, eax
pg_done:
    cmp ebp, 2
    jne fail
    mov eax, cr0
    cmp eax, ebx
    jne fail

    mov al, 1
    out 0xe0, al
    hlt
