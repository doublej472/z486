; A pending interrupt rejected through a not-present gate retains PUSHFD as the
; current opcode.  The #NP handler must still mask the selector out of its own
; IDT gate low DWORD while assembling the target EIP.

BITS 16
org 0

STATUS_PORT       equ 0xE0
SIGNAL_PORT       equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_INSTR_PORT equ 0xF0
SIGNAL_VECTOR_PORT equ 0xF4

STATUS_PASS equ 0x01
INTR_VECTOR equ 0x20
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    db 0x66, 0xEA
    dd pm32_entry
    dw SEL_CODE0

BITS 32
pm32_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x9000

    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al

    mov dx, SIGNAL_INSTR_PORT
    mov ax, 1
    out dx, ax

    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 1
    out dx, ax

    sti
    nop

    mov dx, SIGNAL_PORT
    mov al, 1
    out dx, al

    ; INTR becomes pending as this instruction retires. Vector 20h is not
    ; present, so delivery redirects through the #NP gate with opcode 9Ch
    ; still latched in EX.
    pushfd

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

np_handler:
    mov al, STATUS_PASS
    out STATUS_PORT, al
    hlt

BITS 16
align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08: ring-0 code, base 10000h
    dq 0x00CF93010000FFFF       ; 10: ring-0 data, base 10000h
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    times 11 dq 0
    dw np_handler, SEL_CODE0
    db 0, 10001110b
    dw 0
    times (INTR_VECTOR - 12) dq 0
    dw 0, SEL_CODE0             ; vector 20h: valid gate shape, P=0
    db 0, 00001110b
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000
