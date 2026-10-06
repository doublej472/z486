; div_flags_intel.asm - DIV leaves the 386's flags (Cyrix detection)
;
; The 5/2 test: clear the flags, divide 5 by 2, read them back. A Cyrix CPU
; leaves the flags unchanged (LAHF gives 02h); the 386 leaves the flags of its
; last divide step, 1 - 2 = FFh: SF, AF, PF and CF set, so LAHF gives 97h.

BITS 16
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    xor ax, ax
    sahf
    mov ax, 5
    mov cl, 2
    div cl
    lahf
    cmp ah, 0x02
    je .fail_cyrix
    cmp ah, 0x97
    jne .fail_flags
    cmp al, 2                 ; quotient
    jne .fail_result

    mov al, 0x01
    out STATUS_PORT, al
    hlt

.fail_cyrix:
    mov eax, 1
    jmp .fail
.fail_flags:
    movzx eax, ah
    or eax, 0x200
    jmp .fail
.fail_result:
    mov eax, 3
.fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
