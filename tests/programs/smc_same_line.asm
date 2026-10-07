; smc_same_line.asm - store four distinct instructions into ONE cache line,
; then execute each in turn.  Several stores into one line must all reach the
; following fetches, not only the last one.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

LINE equ 0x2000

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ax, cs
    mov ds, ax          ; DS = CS: stores must hit the code page

    ; four "mov al,imm; ret" at offsets 0,4,8,12 of the same 16-byte line
    mov byte [LINE+0], 0xB0
    mov byte [LINE+1], 0x11
    mov byte [LINE+2], 0xC3
    mov byte [LINE+4], 0xB0
    mov byte [LINE+5], 0x22
    mov byte [LINE+6], 0xC3
    mov byte [LINE+8], 0xB0
    mov byte [LINE+9], 0x33
    mov byte [LINE+10], 0xC3
    mov byte [LINE+12], 0xB0
    mov byte [LINE+13], 0x44
    mov byte [LINE+14], 0xC3

    call LINE+0
    cmp al, 0x11
    jne .fail
    call LINE+4
    cmp al, 0x22
    jne .fail
    call LINE+8
    cmp al, 0x33
    jne .fail
    call LINE+12
    cmp al, 0x44
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
