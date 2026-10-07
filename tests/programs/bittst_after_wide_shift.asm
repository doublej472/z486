; bittst_after_wide_shift.asm - BITTST setup must clear a prior wide shift's
; `overflow`: `shl al,10; bt ebx,0` must give CF=1 without tripping the
; BITTST DIRECT CARRY consistency check.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; Leave the shifter's stale `overflow` set: byte shift by 10 >= width 8.
    mov al, 0x01
    shl al, 10
    ; BITTST setup (LDBSRM) plus a set bit 0.
    mov ebx, 1
    bt  ebx, 0
    jnc .fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
