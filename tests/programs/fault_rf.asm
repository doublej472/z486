; fault_rf - fault frames carry EFLAGS.RF=1, trap frames RF=0
;
; A 486 sets RF in the EFLAGS image it pushes for a fault, so the restarted
; instruction cannot re-trigger its own code breakpoint.  Raise #DE (DIV by
; zero) and #UD (0F 0B) with RF=0 and no breakpoints enabled: both frames
; must have RF set.  INT3 is a trap and must push RF=0.
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 fail code.
BITS 32
ORG 0
RF equ 0x10000
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
    dw de_handler, 8          ; 0: #DE
    db 0, 0x8e
    dw 0
    times 2 dq 0
    dw bp_handler, 8          ; 3: #BP
    db 0, 0x8e
    dw 0
    times 2 dq 0
    dw ud_handler, 8          ; 6: #UD
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

de_handler:
    mov edi, 2
    cmp dword [ss:esp], de_site
    jne fail
    mov edi, 3
    test dword [ss:esp+8], RF
    jz fail
    add dword [ss:esp], 2     ; skip DIV ECX
    inc ebp
    iretd

ud_handler:
    mov edi, 4
    cmp dword [ss:esp], ud_site
    jne fail
    mov edi, 5
    test dword [ss:esp+8], RF
    jz fail
    add dword [ss:esp], 2     ; skip 0F 0B
    inc ebp
    iretd

bp_handler:
    mov edi, 6
    cmp dword [ss:esp], bp_next
    jne fail
    mov edi, 7
    test dword [ss:esp+8], RF
    jnz fail
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
    push dword 0x2              ; RF=0, IF=0
    popfd
    mov edi, 1
    xor edx, edx
    mov eax, 1234
    xor ecx, ecx
de_site:
    div ecx                     ; #DE (fault)
    mov edi, 8
    cmp ebp, 1
    jne fail
    pushfd                      ; the IRET restored RF=1; clear it again
    and dword [esp], ~RF
    popfd
ud_site:
    db 0x0f, 0x0b               ; #UD (fault)
    mov edi, 9
    cmp ebp, 2
    jne fail
    int3                        ; #BP (trap)
bp_next:
    mov edi, 10
    cmp ebp, 3
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
