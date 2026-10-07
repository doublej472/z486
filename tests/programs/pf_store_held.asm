; pf_store_held - a younger read's #PF must not overwrite an older posted
; store's latched #PF code/CR2 (V86 monitors such as EMM386 decode the error
; code).  A store to an unmapped page is posted; a younger load from a second
; unmapped page faults.  The handler records both faults; the store's fault
; must be delivered and its data written.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
DATA_BASE   equ 0x20000000
A_OFF       equ 0x00001000
B_OFF       equ 0x00002000
PTE_A       equ 0x00002004       ; PDE 0x80's PT at 0x2000
PTE_B       equ 0x00002008

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov ax, 0x18
    mov es, ax
    mov ax, 0x10
    mov ds, ax
    mov esp, 0x8000

    mov dword [es:0x5000], 0     ; store-fault count
    mov dword [es:0x5004], 0     ; younger-read-fault count

    mov edx, A_OFF
    mov eax, 0x12345678
    mov [edx], eax               ; posted store -> #PF (older)
    mov edx, B_OFF
    mov ebx, [edx]               ; younger load -> #PF

    cmp dword [es:0x5000], 1
    jne fail
    cmp dword [es:0x5004], 1
    jne fail
    mov edx, A_OFF
    cmp dword [edx], 0x12345678
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

fail:
    mov edx, A_OFF
    mov eax, [edx]
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

pf_handler:
    push eax
    mov eax, cr2
    cmp eax, DATA_BASE + A_OFF
    jne .younger
    inc dword [es:0x5000]
    mov dword [es:PTE_A], 0x21000 | 0x27
    invlpg [A_OFF]
    jmp .done
.younger:
    inc dword [es:0x5004]
    mov dword [es:PTE_B], 0x22000 | 0x27
    invlpg [B_OFF]
.done:
    pop eax
    add esp, 4                   ; discard the #PF error code
    iretd

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff      ; 08: code, base 0x00010000
    dq 0x20cf93000000ffff      ; 10: data, base 0x20000000
    dq 0x00cf93000000ffff      ; 18: flat data, base 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

align 8
idt:
    times 14 dq 0
    dw pf_handler
    dw 0x0008
    db 0, 0x8e
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd 0x00010000 + idt
