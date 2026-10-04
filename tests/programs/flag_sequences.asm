; flag_sequences.asm - multi-instruction flag-carry / dependency chains
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; ---- add ax,bx -> adc ax,cx ----
    mov ax,0xFFFF
    mov bx,1
    mov cx,0
    add ax,bx
    adc ax,cx
    cmp ax, 0x0001
    jne .fail

    ; ---- sub ax,bx -> sbb ax,cx ----
    mov ax,0
    mov bx,1
    mov cx,0
    sub ax,bx
    sbb ax,cx
    cmp ax, 0xfffe
    jne .fail

    ; ---- shl ax,1 -> adc bx,0 ----
    mov ax,0x8000
    mov bx,0
    shl ax,1
    adc bx,0
    cmp bx, 0x0001
    jne .fail

    ; ---- stc;inc ax;adc bx,0 ----
    mov ax,0
    mov bx,0
    stc
    inc ax
    adc bx,0
    cmp bx, 0x0001
    jne .fail

    ; ---- mov ah,0x12;mov al,0x34 ----
    mov ah,0x12
    mov al,0x34
    cmp ax, 0x1234
    jne .fail

    ; ---- neg ax -> adc ax,bx ----
    mov ax,0
    mov bx,1
    neg ax
    adc ax,bx
    cmp ax, 0x0001
    jne .fail

    ; ---- shl;rol;rcr chain ----
    mov ax,0x8001
    shl ax,1
    rol ax,1
    rcr ax,1
    cmp ax, 0x0002
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
