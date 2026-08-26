; popss_shadow.asm - Verify POP SS interrupt shadow with hardware INTR

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SIGNAL_PORT equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_INSTR_PORT  equ 0xF0
SIGNAL_VECTOR_PORT equ 0xF4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF
INTR_VECTOR equ 0x20

start:
    cli
    cld

    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov es, ax
    mov word [es:INTR_VECTOR*4], isr_intr
    mov word [es:INTR_VECTOR*4+2], 0x1000

    mov word [intr_count], 0
    mov byte [marker], 0
    mov byte [intr_seen_marker], 0

    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al
    mov dx, SIGNAL_INSTR_PORT
    mov ax, 1
    out dx, ax
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 1
    out dx, ax

    mov ax, ss
    push ax
    mov dx, SIGNAL_PORT
    mov ax, 1
    out dx, ax
    sti
    pop ss                  ; extends the shadow through the next instruction
    mov byte [marker], 1
    nop

    mov cx, 10000
.wait_intr:
    cmp word [intr_count], 1
    je .intr_ok
    dec cx
    jnz .wait_intr
    mov eax, 1
    jmp fail

.intr_ok:
    cmp byte [intr_seen_marker], 1
    jne .fail_shadow
    cmp word [intr_count], 1
    jne .fail_count

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

.fail_shadow:
    mov eax, 2
    jmp fail
.fail_count:
    mov eax, 3

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

isr_intr:
    push ax
    mov al, [cs:marker]
    mov [cs:intr_seen_marker], al
    inc word [cs:intr_count]
    pop ax
    iret

align 2
intr_count:       dw 0
marker:           db 0
intr_seen_marker: db 0
