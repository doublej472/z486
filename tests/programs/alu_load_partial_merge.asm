; alu_load_partial_merge.asm - an ALU load followed by a byte or word load
; into the same register (found by differential fuzzing)
;
; A direct load merges a byte or word into its destination's prior value,
; captured before the load's data arrives. The ALU load's M3 result is not
; forwarded to that capture, so the narrow load must not take the ALU load's
; dead slot. Each case clears the register, adds a dword from memory, then
; loads a narrow value into part of it.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
CODE_BASE   equ 0x10000

start:
    mov esp, 0x3F000
    mov ebp, CODE_BASE + d0
again:                                  ; second pass runs from the caches

    ; 1: MOV r8 low
    xor eax, eax
    xor edi, ecx
    add eax, [ebp + d0 - d0]
    mov al, [ebp + d1 - d0]
    cmp eax, 0x13b2ce5a
    jne fail

    ; 2: MOV r8 high
    xor ecx, ecx
    xor edi, ecx
    add ecx, [ebp + d0 - d0]
    mov ch, [ebp + d1 - d0]
    cmp ecx, 0x13b25aa8
    jne fail

    ; 3: MOV r16
    xor edx, edx
    xor edi, ecx
    add edx, [ebp + d0 - d0]
    mov dx, [ebp + d1 - d0]
    cmp edx, 0x13b27c5a
    jne fail

    ; 4: MOVZX r16
    xor ebx, ebx
    xor edi, ecx
    add ebx, [ebp + d0 - d0]
    movzx bx, byte [ebp + d1 - d0]
    cmp ebx, 0x13b2005a
    jne fail

    ; 5: POP r16
    push word 0x1234
    xor esi, esi
    xor edi, ecx
    add esi, [ebp + d0 - d0]
    pop si
    cmp esi, 0x13b21234
    jne fail

    dec dword [ebp + passes - d0]
    jnz again
    mov al, 0x01
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 4
d0: dd 0x13b2cea8
d1: dw 0x7c5a
align 4
passes: dd 2

times 0x400 - ($ - $$) db 0
