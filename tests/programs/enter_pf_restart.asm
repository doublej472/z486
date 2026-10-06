; An ENTER whose new stack top is on a not-present page faults in ENTER and
; restarts there: the 386 microcode probes the final ESP (CW) after pushing
; EBP, before committing ESP. The #PF frame holds ENTER's EIP and the ESP it
; started with. z486 took the frame from the restart state of the last
; microcode-path write, an older instruction, so the handler returned into
; code that had already run (Win95 first run: ADDREG #GP in KRNL386).

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CODE_BASE   equ 0x00010000
DATA        equ 0x00020000
STACK_TOP   equ 0x00031040
LO_PAGE     equ 0x00030000
LO_PTE      equ 0x00001000 + (LO_PAGE >> 12) * 4

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
    mov eax, [esp + 8]                  ; frame EIP (after the error code)
    mov [CODE_BASE + pf_eip], eax
    lea eax, [esp + 20]                 ; ESP before the fault frame
    mov [CODE_BASE + pf_esp], eax
    pop eax
    inc dword [CODE_BASE + pf_count]
    or dword [LO_PTE], 1
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
pf_eip:   dd 0
pf_esp:   dd 0

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    and dword [LO_PTE], 0xFFFFFFFE
    invlpg [LO_PAGE]
    mov esp, STACK_TOP
    mov ebp, 0x5A5A5A5A

    ; An ordinary store, then a few instructions, then the ENTER.
    mov eax, 0x13572468
    mov [DATA + 0x84], eax
    mov ecx, 3
    push ecx
    pop ecx
enter1:
    enter 0x60, 0                       ; CW at STACK_TOP-4-0x60: #PF, restarted
    cmp dword [CODE_BASE + pf_count], 1
    mov ebx, 0x10
    jne fail
    cmp dword [CODE_BASE + pf_eip], enter1
    mov ebx, 0x11
    jne fail
    cmp dword [CODE_BASE + pf_esp], STACK_TOP
    mov ebx, 0x12
    jne fail
    cmp ebp, STACK_TOP - 4
    mov ebx, 0x13
    jne fail
    cmp esp, STACK_TOP - 4 - 0x60
    mov ebx, 0x14
    jne fail
    cmp dword [STACK_TOP - 4], 0x5A5A5A5A
    mov ebx, 0x15
    jne fail

    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov eax, ebx
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
