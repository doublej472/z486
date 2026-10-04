; of_stack_vs_ds.asm - the same 1-bit SHL (0x80000000 -> 0, CF=1 OF=1 ZF=1)
; with a DS-based operand and with an ESP-based operand, and then with the value
; pushed on the stack so the microcode chains the stack op with the shift.
; Each case prints raw EFLAGS then the stored result.  All three flag words must
; be 0x847 and all three results 0.
BITS 32
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
D1 equ 0x4000
start:
    mov esp, 0x3000

    ; 1: DS-based operand
    mov dword [D1], 0x80000000
    shl dword [D1], 1
    pushfd
    pop eax
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [D1]
    out dx, eax

    ; 2: ESP-based operand
    mov dword [esp+8], 0x80000000
    shl dword [esp+8], 1
    pushfd
    pop eax
    out dx, eax
    mov eax, [esp+8]
    out dx, eax

    ; 3: value pushed, shift on [esp], then pop it back
    push dword 0x80000000
    shl dword [esp], 1
    pushfd
    pop eax
    out dx, eax
    pop eax
    out dx, eax
    cmp esp, 0x3000
    jne fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
