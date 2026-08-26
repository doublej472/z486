; An INTR after direct VIPT ALU retirement must observe the completed
; destination and flags.

BITS 16
org 0

STATUS_PORT        equ 0xE0
DATA_PORT          equ 0xE4
SIGNAL_PORT        equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_VECTOR_PORT equ 0xF4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF
INTR_VECTOR equ 0x20
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
PM_STACK_TOP equ 0x9000
LOAD_VALUE  equ 3

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
    mov dword [intr_eax], 0
    mov dword [intr_eflags], 0
    mov dword [load_value], LOAD_VALUE
    times 32 nop
    mov edx, [load_value]
    times 8 nop

    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al
    sti
    nop

    ; Leave enough clocks for the registered direct result to retire, then
    ; take INTR from a flag-preserving JMP loop.
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 20
    out dx, ax
    mov dx, SIGNAL_PORT
    mov al, 1
    out dx, al

    mov eax, 0xffffffff
    add eax, [load_value]
wait_for_intr:
    jmp wait_for_intr
after_intr:

    cmp dword [intr_count], 1
    jne fail1
    cmp dword [intr_eax], 2
    jne fail2
    test dword [intr_eflags], 1
    jz fail3

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

isr_intr:
    mov [intr_eax], eax
    pushfd
    pop dword [intr_eflags]
    mov dword [ss:esp], after_intr
    inc dword [intr_count]
    iretd

fail1: mov eax, 1
    jmp fail
fail2: mov eax, 2
    jmp fail
fail3: mov eax, 3
    jmp fail
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

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
intr_count:     dd 0
intr_eax:       dd 0
intr_eflags:    dd 0
align 64
load_value:     dd 0
