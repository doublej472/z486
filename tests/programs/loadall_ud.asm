; loadall_ud - 0F 07 (the 80386 LOADALL) raises #UD on a 486
;
; The 80386 microcode ROM this core runs still holds LOADALL behind 0F 07.
; The 486 removed it, and running the old routine hung the CPU.  Execute it
; at CPL0 in protected mode: #UD must be raised with CS:EIP naming the
; instruction, the registers unchanged, and execution continuing after it.
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 fail code.
BITS 32
ORG 0
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 08: code, base 0x10000
    dq 0x00cf93020000ffff     ; 10: data, base 0x20000
    dq 0x00cf93030000ffff     ; 18: stack, base 0x30000
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt
align 8
idt:
    times 6 dq 0
    dw ud_handler, 8
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

ud_handler:
    mov edi, 2
    cmp dword [ss:esp], loadall_site
    jne fail
    mov edi, 3
    cmp dword [ss:esp+4], 8
    jne fail
    add dword [ss:esp], 2     ; skip 0F 07
    inc ebp
    iretd

fail:
    mov eax, edi
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt

times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0xf00
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    xor ebp, ebp
    mov eax, 0x11223344
    mov ebx, 0x55667788
    mov esi, 0x800
    mov edi, 1
loadall_site:
    db 0x0f, 0x07              ; LOADALL (80386)
    mov edi, 4
    cmp ebp, 1                 ; exactly one #UD
    jne fail
    mov edi, 5
    cmp eax, 0x11223344
    jne fail
    cmp ebx, 0x55667788
    jne fail
    cmp esi, 0x800
    jne fail
    cmp esp, 0xf00
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
