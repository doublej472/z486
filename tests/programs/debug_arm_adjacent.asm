; debug_arm_adjacent - a breakpoint armed by the immediately preceding
; MOV DR7 / MOV DRn must catch the very next instruction's access.
; (MOV to a debug register takes effect for the following instruction;
; Intel486 PRM 11.2.)  Each case: (case << 8) | count to port 0xE4 when the
; trap count is not exactly 1 or the EIP is wrong.
BITS 32
ORG 0
CODE_BASE equ 0x10000
X equ 0x9000
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
    mov eax, [esp + 4]
    mov [0x5004], eax
    inc dword [0x5000]
    xor eax, eax
    mov dr7, eax
    mov dr6, eax
    pop eax
    iretd

; ecx case, edx expected EIP
check:
    xor eax, eax
    mov dr7, eax
    cmp dword [0x5000], 1
    jne .bad
    cmp [0x5004], edx
    jne .bad
    ret
.bad:
    mov eax, ecx
    shl eax, 8
    or eax, [0x5000]
    out 0xe4, eax
    mov eax, [0x5004]
    out 0xe4, eax
    inc dword [0x5008]
    ret

%macro PREP 0
    mov dword [0x5000], 0
    mov dword [0x5004], 0
    mov esi, X+0x100
    mov edi, X
    mov ebx, X
%endmacro

times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    mov dword [0x5008], 0
    cld
    mov eax, X
    mov dr0, eax

    ; 1 DR7 then store
    PREP
    mov eax, 0x000d0001
    mov dr7, eax
    mov dword [X], 1
e1: mov ecx, 1
    mov edx, e1
    call check
    ; 2 DR7 then load
    PREP
    mov eax, 0x000f0001
    mov dr7, eax
    mov ecx, [X]
e2: mov ecx, 2
    mov edx, e2
    call check
    ; 3 DR7 then load via base register
    PREP
    mov eax, 0x000f0001
    mov dr7, eax
    mov ecx, [ebx]
e3: mov ecx, 3
    mov edx, e3
    call check
    ; 4 DR7 then RMW
    PREP
    mov eax, 0x000d0001
    mov dr7, eax
    add dword [ebx], 1
e4: mov ecx, 4
    mov edx, e4
    call check
    ; 5 DR7 then MOVSD
    PREP
    mov eax, 0x000d0001
    mov dr7, eax
    movsd
e5: mov ecx, 5
    mov edx, e5
    call check
    ; 6 DR0 retargeted (DR7 already on) then load
    PREP
    mov eax, 0x9800
    mov dr0, eax
    mov eax, 0x000f0001
    mov dr7, eax
    mov eax, X
    mov dr0, eax
    mov ecx, [X]
e6: mov ecx, 6
    mov edx, e6
    call check
    ; 8 DR7 then load, both in one cache line, after a warm-up of the load
    PREP
    mov ecx, [X]
    mov eax, 0x000f0001
    mov dr7, eax
    mov ecx, [X]
e8: mov ecx, 8
    mov edx, e8
    call check

    cmp dword [0x5008], 0
    jne bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov al, 0xff
    out 0xe0, al
    hlt
