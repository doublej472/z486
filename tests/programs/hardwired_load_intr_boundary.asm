; A pending INTR at a hardwired moffs-load boundary must not suppress the
; load's writeback when a younger VIPT load shadows the ROM delay slot.

BITS 16
org 0

STATUS_PORT       equ 0xE0
DATA_PORT         equ 0xE4
SIGNAL_PORT       equ 0xE8
SIGNAL_VECTOR_PORT equ 0xF4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF
INTR_VECTOR equ 0x20
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
PM_STACK_TOP equ 0x9000
LOAD_VALUE  equ 0x5A17C0DE

start:
    cli
    cld
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov eax, cr0
    or eax, 0x80000001
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
    mov esp, PM_STACK_TOP

    mov dword [intr_count], 0
    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al
    sti
    nop

    ; Testbench mode 4 aligns INTR with the A1/VIPT-successor race from Quake.
    mov dx, SIGNAL_PORT
    mov al, 4
    out dx, al
    mov eax, 0xBAD0BAD0
    mov eax, [load_value]
    ; Keep a VIPT-eligible ModR/M load in D2 at the A1 retirement boundary,
    ; matching Quake's A1 followed by 8B /r sequence.
    mov edx, [load_value2]

    cmp eax, LOAD_VALUE
    jne .fail_load
    cmp dword [intr_count], 1
    jne .fail_irq

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail_load:
    mov dx, DATA_PORT
    out dx, eax
    mov eax, 1
    jmp fail
.fail_irq:
    mov eax, 2
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

isr_intr:
    inc dword [intr_count]
    iretd

BITS 16
align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF
    dq 0x00CF93010000FFFF
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times INTR_VECTOR dq 0
    dw isr_intr
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
    times (256 - INTR_VECTOR - 1) dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

BITS 32
align 4
intr_count: dd 0
align 64
load_value: dd LOAD_VALUE
load_value2: dd 0x12345678
