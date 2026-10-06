; push_pf_stack_restart.asm - a PUSH whose write faults restarts with its own ESP
;
; Ring 3 pushes twice onto a stack page whose PTE is clear. The first PUSH
; posts its write and the second issues behind it; the write then faults.
; The #PF frame must name the first PUSH with the ESP it started with
; (Quake 1.06 under CWSDPMI crashed when it named the second PUSH's ESP).
; The ring-0 handler maps the page and both pushes complete on restart.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CODE_BASE   equ 0x00010000
USTACK      equ 0x00030000                  ; user stack page, top at +0x1000
USTACK_PTE  equ 0x00001000 + (USTACK >> 12) * 4
KSTACK_TOP  equ 0x00038000
VAL1        equ 0x11223344
VAL2        equ 0x55667788

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff                   ; 0x08: ring 0 code, base 0x10000
    dq 0x00cf93000000ffff                   ; 0x10: ring 0 data, base 0
    dq 0x00cffb010000ffff                   ; 0x18: ring 3 code, base 0x10000
    dq 0x00cff3000000ffff                   ; 0x20: ring 3 data, base 0
    dw 0x0067                               ; 0x28: 386 TSS
    dw tss
    db 0x01
    db 0x89
    db 0x00
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_BASE + gdt

align 8
idt:
    times 14 dq 0
    dw pf_handler
    dw SEL_CODE0
    db 0
    db 0x8e
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_BASE + idt

align 4
tss:
    dd 0
    dd KSTACK_TOP                           ; ESP0
    dd SEL_DATA0                            ; SS0
    times 23 dd 0

align 4
pf_count: dd 0
pf_eip:   dd 0
pf_esp:   dd 0

pf_handler:
    ; frame: [esp]=error code, +4 EIP, +8 CS, +12 EFLAGS, +16 ESP3, +20 SS3
    push eax
    push ds
    mov ax, SEL_DATA0
    mov ds, ax
    inc dword [CODE_BASE + pf_count]
    cmp dword [CODE_BASE + pf_count], 1
    jne .map
    mov eax, [esp + 12]
    mov [CODE_BASE + pf_eip], eax
    mov eax, [esp + 24]
    mov [CODE_BASE + pf_esp], eax
.map:
    or dword [USTACK_PTE], 1
    pop ds
    pop eax
    add esp, 4                              ; error code
    iretd

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, KSTACK_TOP
    mov ax, SEL_TSS
    ltr ax
    and dword [USTACK_PTE], 0xFFFFFFFE
    invlpg [USTACK]
    push dword SEL_DATA3 | 3                ; SS3
    push dword USTACK + 0x1000              ; ESP3
    push dword 0x00003002                   ; EFLAGS, IOPL 3
    push dword SEL_CODE3 | 3                ; CS3
    push dword ring3
    iretd

ring3:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    mov es, ax
    mov eax, VAL1
    mov ecx, VAL2
push1:
    push eax
    push ecx
    mov edx, 1
    cmp esp, USTACK + 0x1000 - 8
    jne fail
    mov edx, 2
    cmp dword [USTACK + 0xffc], VAL1
    jne fail
    cmp dword [USTACK + 0xff8], VAL2
    jne fail
    mov edx, 3
    cmp dword [CODE_BASE + pf_count], 1
    jne fail
    mov edx, 4
    cmp dword [CODE_BASE + pf_eip], push1
    jne fail
    mov edx, 5
    cmp dword [CODE_BASE + pf_esp], USTACK + 0x1000
    jne fail
    mov al, 1
    out STATUS_PORT, al
    jmp $

fail:
    mov eax, edx
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    jmp $

times 0x400 - ($ - $$) db 0
