; smc_basic.asm - self-modifying code: store "mov ax,0xBEEF; ret" into a
; code buffer, call it, and verify ax. The store must invalidate/update the
; I-cache line so the call executes the new instruction, not the NOP filler.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ax, cs
    mov ds, ax          ; DS = CS: the store must hit the code page

    ; write B8 EF BE C3  ("mov ax,0xBEEF; ret") into buf
    mov byte [buf+0], 0xB8
    mov byte [buf+1], 0xEF
    mov byte [buf+2], 0xBE
    mov byte [buf+3], 0xC3

    call buf
    cmp ax, 0xBEEF
    jne .fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 16
buf:
    times 16 db 0x90    ; NOP filler, overwritten by the store above
