; debug_ss_shadow - TF single step across MOV SS / POP SS
;
; MOV SS and POP SS inhibit interrupts and debug exceptions until after the
; next instruction (Intel486 PRM 26 MOV/POP pages: "inhibits all interrupts,
; including NMI, until after execution of the next instruction").  With TF=1
; the trap after MOV SS is taken after the following instruction: the step
; log is <..., after_next> without an entry naming the instruction after
; MOV SS.  Port 0xE4: failing check, then the logged EIPs.
BITS 32
ORG 0
CODE_BASE equ 0x10000
LOG equ 0x5000
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd CODE_BASE+gdt
align 8
idt:
    dq 0
    dw db_handler, 8
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd CODE_BASE+idt
db_handler:
    push eax
    push ebx
    mov ebx, ebp
    and ebx, 15
    mov eax, [esp + 8]
    mov [LOG + ebx*4], eax
    inc ebp
    xor eax, eax
    mov dr6, eax
    pop ebx
    pop eax
    iretd
times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    xor ebp, ebp
    mov ax, 0x10
    pushfd
    or dword [esp], 0x100
    popfd
    nop                                ; trap 0 -> EIP a0
a0: mov ss, ax                         ; no trap here (shadow)
a1: nop                                ; trap 1 -> EIP a2
a2: push dword 0x10
a3: pop ss                             ; shadow
a4: nop
a5: pushfd
    and dword [esp], ~0x100
    popfd
    nop
    mov ebx, 1
    cmp dword [LOG], a0
    jne fail
    mov ebx, 2
    cmp dword [LOG+4], a2
    jne fail
    mov ebx, 3
    cmp dword [LOG+8], a3
    jne fail
    mov ebx, 4
    cmp dword [LOG+12], a5
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, ebx
    out 0xe4, eax
    mov eax, [LOG]
    out 0xe4, eax
    mov eax, [LOG+4]
    out 0xe4, eax
    mov eax, [LOG+8]
    out 0xe4, eax
    mov eax, [LOG+12]
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
