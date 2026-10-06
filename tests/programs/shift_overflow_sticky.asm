; shift_overflow_sticky.asm - a shift whose count reaches the operand width
; (found by differential fuzzing with injection)
;
; SHL/SHR/SAL/SAR with a count of at least the operand width set the
; shifter's overflow state, which forces a zero result. SHLD/SHRD and the
; LDBSRM setup used by IMUL r, r/m, imm must not inherit it.

BITS 32
ORG 0

STATUS_PORT equ 0xE0

start:
    mov esp, 0x3F000

    ; 1: SHRD after a byte shift by 12
    mov al, 0x5a
    shl al, 12
    mov ebx, 0x34
    mov edi, 0xfd6edf94
    shrd ebx, edi, 27
    cmp ebx, 0xaddbf280
    jne fail

    ; 2: SHLD after a word shift by 16
    mov ax, 0x1234
    shr ax, 16
    mov edx, 0x80000001
    mov esi, 0xc0000000
    shld edx, esi, 4
    cmp edx, 0x0000001c
    jne fail

    ; 3: IMUL r, r, imm8 after a byte shift by 9
    mov al, 0x81
    sar al, 9
    mov ecx, 0xa6cb8c70
    imul ebx, ecx, 18
    cmp ebx, 0xba4fdfe0
    jne fail

    ; 4: IMUL r, r, imm32 after a byte shift by 8
    mov al, 0x81
    shl al, 8
    mov ecx, 7
    imul ebx, ecx, 0x10001
    cmp ebx, 0x70007
    jne fail

    mov al, 0x01
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
