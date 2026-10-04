; aaa_halfcarry.asm - AAA is the 16-bit AX + 0x0106 (AL carry propagates
; into AH), then AL's high nibble clears. AX=0x00FF -> 0x0205.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; AX = 0x00FF: (AL & 0xF) = 0xF > 9 forces the adjust.
    ; AX + 0x0106 = 0x0205 (AL+6 carries into AH, AH+1).  Expected AX = 0x0205.
    mov ax, 0x00FF
    aaa
    cmp ax, 0x0205
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
