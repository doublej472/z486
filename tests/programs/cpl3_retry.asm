; cpl3_retry - ring-3 fault whose ring-0 handler maps the page and IRETs, so the
; instruction retries.  SEL_LOAD selects a data load (control) or a stack PUSH
; (the store whose restart ESP is in question).  A loop means the retry re-faults
; instead of advancing.
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

%ifndef RETRY_KIND
%define RETRY_KIND 0                 ; 0 = ring-3 load, 1 = ring-3 PUSH
%endif

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
%if RETRY_KIND = 1
    mov eax, 0x12345678
    push eax
    pop eax
%else
    mov eax, [FAULT_PAGE]
%endif
    mov dword [0x1800], 1           ; reached without a loop
    int 0x21
bad3:
    hlt
    jmp $

pf_handler:
    mov dword [FAULT_PTE], FAULT_PAGE | 0x27
    invlpg [FAULT_PAGE]
    add esp, 4
    iretd

report_handler:
    mov ax, SEL_DATA0
    mov ds, ax
    mov al, 1
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
