; aas_halfborrow.asm - AAS is the 16-bit AX - 0x0106 (AL borrow propagates
; into AH), then AL's high nibble clears. AX=0x0105,AF=1 -> 0xFF0F.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; Force AF=1 via SAHF (bit 4 of the value loaded into the flags byte).
    mov ax, 0x1005              ; AH = 0x10 carries the AF bit
    sahf                        ; AF = 1, CF = 0
    mov ax, 0x0105              ; AH = 0x01, AL = 0x05; MOV leaves flags alone
    aas                         ; AX - 0x0106 = 0xFFFF, AL & 0x0F -> 0x0F.
                                ; Expected AX = 0xFF0F.
    cmp ax, 0xFF0F
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
