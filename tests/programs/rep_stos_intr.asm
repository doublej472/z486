; rep_stos_intr.asm - interruptible optimized REP STOS restart boundary
;
; The optimized loop commits ECX beside EDI only after each accepted store.
; Force an interrupt in the middle and verify the handler sees the next
; element's restart state before REP resumes to completion.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SIGNAL_PORT equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_VECTOR_PORT equ 0xF4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
INTR_VECTOR equ 0x20
REP_COUNT   equ 64
PATTERN     equ 0x51A7C0DE

start:
    cli
    cld
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
    mov esp, stack_top

    mov dword [intr_count], 0
    mov dword [intr_ecx], 0
    mov dword [intr_edi], 0

    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 8
    out dx, ax

    mov ecx, REP_COUNT
    mov edi, buffer
    mov eax, PATTERN
    sti
    mov dx, SIGNAL_PORT
    mov al, 1
    out dx, al

    mov eax, PATTERN
    rep stosd

    cmp dword [intr_count], 1
    jne fail_no_irq
    cmp dword [intr_ecx], 0
    je fail_irq_zero
    cmp dword [intr_ecx], REP_COUNT
    jae fail_irq_range
    mov eax, REP_COUNT
    sub eax, [intr_ecx]
    shl eax, 2
    add eax, buffer
    cmp eax, [intr_edi]
    jne fail_irq_edi
    test ecx, ecx
    jne fail_final_state
    cmp edi, buffer + REP_COUNT * 4
    jne fail_final_state

    mov esi, buffer
    mov ecx, REP_COUNT
.check:
    cmp dword [esi], PATTERN
    jne fail_data
    add esi, 4
    loop .check

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

irq_handler:
    inc dword [intr_count]
    mov [intr_ecx], ecx
    mov [intr_edi], edi
    iretd

fail_no_irq:
    mov eax, 1
    jmp fail
fail_irq_zero:
    mov eax, 0x21
    jmp fail
fail_irq_range:
    mov eax, 0x22
    jmp fail
fail_irq_edi:
    mov eax, 0x23
    jmp fail
fail_final_state:
    mov eax, 3
    jmp fail
fail_data:
    mov eax, 4
    jmp fail
ud_handler:
    mov eax, 0x600
    jmp fail
gp_handler:
    mov eax, 0xd00
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

BITS 16
align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF
    dq 0x00CF93010000FFFF
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    times 6 dq 0
    dw ud_handler, SEL_CODE0
    db 0, 10001110b
    dw 0
    times (13 - 7) dq 0
    dw gp_handler, SEL_CODE0
    db 0, 10001110b
    dw 0
    times (INTR_VECTOR - 14) dq 0
    dw irq_handler, SEL_CODE0
    db 0, 10001110b
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

BITS 32
align 4
intr_count: dd 0
intr_ecx: dd 0
intr_edi: dd 0
buffer: times REP_COUNT dd 0
stack: times 512 db 0
stack_top:
