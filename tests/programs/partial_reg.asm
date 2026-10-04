; partial_reg.asm - AH/AL partial-register interleaving: write high byte, write
; low byte, and read back AX/AH/AL across instructions.
BITS 16
org 0
STATUS_PORT equ 0xE0

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    mov ah, 0x48
    mov al, 0x12
    cmp ax, 0x4812
    jne .fail

    mov ah, 0x77
    mov al, ah
    cmp al, 0x77
    jne .fail

    mov ax, 0x1234
    mov al, 0x56
    cmp ax, 0x1256
    jne .fail

    mov ax, 0x1234
    mov ah, 0x56
    cmp ax, 0x5634
    jne .fail


    mov al, 0x34
    mov ah, 0x12
    cmp ax, 0x1234
    jne .fail

    mov ah, 0xAB
    mov al, 0xCD
    cmp ax, 0xABCD
    jne .fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
