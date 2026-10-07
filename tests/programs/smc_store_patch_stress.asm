; smc_store_patch_stress.asm - store five distinct "mov al,imm; ret" into five
; distinct cache lines, then execute each in order.  More stores into code
; lines back to back than the D$->I$ store-coherence path holds at once (the
; fork's old 3-deep store-patch queue; now the store-invalidate slot).
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

LINE0 equ 0x1000

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ax, cs
    mov ds, ax          ; DS = CS: stores must hit the code page

    ; line k at LINE0 + k*0x100: "mov al, 0x10+k; ret" = B0 (0x10+k) C3
    mov si, LINE0
    mov cl, 5
    mov dl, 0x10
.store_loop:
    mov byte [si], 0xB0
    mov byte [si+1], dl
    mov byte [si+2], 0xC3
    add si, 0x100
    inc dl
    dec cl
    jnz .store_loop

    ; execute each and verify al == 0x10+k
    mov si, LINE0
    mov cl, 5
    mov dl, 0x10
.exec_loop:
    call si
    cmp al, dl
    jne .fail
    add si, 0x100
    inc dl
    dec cl
    jnz .exec_loop

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
