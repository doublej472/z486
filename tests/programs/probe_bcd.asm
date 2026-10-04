; DAA/DAS/AAM/AAD - uncovered BCD instruction probe
BITS 32
ORG 0
STATUS_PORT equ 0xE0
start:
    cli
    mov esp, 0x00003F00
; DAA: 0x0F -> 0x15 (low nibble > 9 adds 6), CF clear
    mov al, 0x0F
    daa
    cmp al, 0x15
    jne fail
; DAS: 0x21 - 0x02 = 0x1F, AF set -> 0x19
    mov al, 0x21
    sub al, 0x02
    das
    cmp al, 0x19
    jne fail
; AAM: AL=0x0C -> AH=1, AL=2
    mov ax, 0x000C
    aam
    cmp ah, 1
    jne fail
    cmp al, 2
    jne fail
; AAD: AH=1, AL=2 -> AL=12, AH=0
    mov ax, 0x0102
    aad
    cmp al, 0x0C
    jne fail
    cmp ah, 0
    jne fail
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
