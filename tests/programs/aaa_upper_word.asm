; aaa_upper_word.asm - AAA adjusts AX only; EAX[31:16] must survive even when
; the AL carry propagates through AH (AH=0xFF).  A full-width 32-bit +0x0106
; would carry out of bit 15 and corrupt the upper word.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; EAX = 0x1234FFFF.  (AL & 0xF)=0xF forces the adjust, and AH+1+carry
    ; overflows, so the wide form carries into EAX[31:16].
    ; Correct: AX = 0xFFFF + 0x0106 = 0x0105, AL high nibble cleared -> 0x0105,
    ; upper word untouched -> EAX = 0x12340105.
    mov eax, 0x1234FFFF
    aaa
    cmp eax, 0x12340105
    jne .fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
