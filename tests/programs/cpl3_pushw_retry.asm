; cpl3_pushw_retry - four ring-3 register PUSHes; the first crosses into a
; not-present stack page.  The ring-0 handler maps the page and IRETs, so the
; PUSH must retry with its own ESP.  Every slot and the final ESP must match,
; which fails if the retry decrements ESP twice.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28

R3_STACK    equ 0x00003000
R0_STACK    equ 0x00014000
FAULT_PAGE  equ 0x00002000
FAULT_PTE   equ 0x00001008

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, R0_STACK
    mov ax, SEL_TSS
    ltr ax

    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    push dword SEL_DATA3 | 3
    push dword R3_STACK
    pushfd
    or  dword [esp], 0x200
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    mov ax, 0x1111
    push ax
    mov ax, 0x2222
    push ax
    mov ax, 0x3333
    push ax
    mov ax, 0x4444
    push ax
    mov [0x1800], esp            ; ESP after four word PUSHes (expect 0x2FF8)
    movzx eax, word [0x2FFE]
    mov [0x1804], eax
    movzx eax, word [0x2FFC]
    mov [0x1808], eax
    movzx eax, word [0x2FFA]
    mov [0x180C], eax
    movzx eax, word [0x2FF8]
    mov [0x1810], eax
    int 0x21

pf_handler:
    inc dword [0x1820]           ; fault count
    mov dword [FAULT_PTE], FAULT_PAGE | 0x27
    invlpg [FAULT_PAGE]
    add esp, 4
    iretd

report_handler:
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, [0x1820]
    cmp eax, 1                   ; exactly one #PF
    jne .fail
    mov eax, [0x1800]
    cmp eax, 0x00002FF8          ; ESP after four word PUSHes
    jne .fail
    mov eax, [0x1804]
    cmp eax, 0x1111
    jne .fail
    mov eax, [0x1808]
    cmp eax, 0x2222
    jne .fail
    mov eax, [0x180C]
    cmp eax, 0x3333
    jne .fail
    mov eax, [0x1810]
    cmp eax, 0x4444
    jne .fail
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt
.fail:
    mov al, 0xff
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
    dq 0x00cffb010000ffff
    dq 0x00cff3000000ffff
tss_desc:
    dw 0x0067
    dw tss
    db 0x01
    db 0x89
    db 0x00
    db 0x00
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    times 14 dq 0
    dw pf_handler
    dw SEL_CODE0
    db 0, 0x8e
    dw 0
    times (0x21 - 15) dq 0
    dw report_handler
    dw SEL_CODE0
    db 0, 0xee
    dw 0
    times (256 - 0x22) dq 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    dd 0, R0_STACK, SEL_DATA0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 104
