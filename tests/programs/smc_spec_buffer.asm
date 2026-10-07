; smc_spec_buffer - self-modifying code vs the prefetcher's branch-target buffer
;
; Each case is a 4-iteration loop whose body patches the imm32 of the
; "mov eax, imm32" at the loop's own branch target, then branches back.  On a
; 486 the taken branch after the store must fetch the modified code, so every
; case must sum 0+1+2+3 = 6.  Failure data = bitmask of failing cases.  The loop target line is held in the prefetcher's
; spec_line buffer by the back-edge branch.
;   case 1 (control): plain MOV store to the target's linear address.
;   case 2: ADD [mem], imm to an aligned imm32 (RMW_FAST direct store port).
;   case 6: INC [mem] (rmw-unary-fast).
;   case 5: aligned plain MOV store (WR_FAST direct store port, st_take).
;   case 3: misaligned dword store whose SECOND half lands in the target line.
;   case 4: plain MOV through a linear alias (0x200000 -> same physical page).
BITS 32
ORG 0
CODE_BASE equ 0x10000
ALIAS     equ 0x200000 - CODE_BASE   ; alias linear = ALIAS + CODE_BASE + off

start:
    mov esp, 0x8000
    xor edi, edi                     ; bit n set = case n failed

    ; ---- case 1: control, plain store ----
    mov ecx, 4
    xor ebx, ebx
    xor edx, edx
    jmp c1_top
    align 16
c1_top:
    mov eax, 0
    add ebx, eax
    inc edx
    mov [CODE_BASE + c1_top + 1], edx
    dec ecx
    jnz c1_top
    cmp ebx, 6
    je ok_1
    or edi, 1 << 1
ok_1:

    ; ---- case 2: RMW store (dword-aligned imm32: RMW_FAST direct port) ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c2_top
    align 16
c2_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c2_top + 4 (aligned)
    add ebx, eax
    add [CODE_BASE + c2_top + 4], esi  ; 01 /r: rmw-m-r-fast recipe
    dec ecx
    jnz c2_top
    cmp ebx, 6
    je ok_2
    or edi, 1 << 2
ok_2:

    ; ---- case 5: aligned plain MOV store (direct WR_FAST port, st_take) ----
    mov ecx, 4
    xor ebx, ebx
    xor edx, edx
    jmp c5_top
    align 16
c5_top:
    nop
    nop
    nop
    mov eax, 0
    add ebx, eax
    inc edx
    mov [CODE_BASE + c5_top + 4], edx
    dec ecx
    jnz c5_top
    cmp ebx, 6
    je ok_5
    or edi, 1 << 5
ok_5:

    ; ---- case 6: INC [mem] (rmw-unary-fast recipe) ----
    mov ecx, 4
    xor ebx, ebx
    jmp c6_top
    align 16
c6_top:
    nop
    nop
    nop
    mov eax, 0
    add ebx, eax
    inc dword [CODE_BASE + c6_top + 4]
    dec ecx
    jnz c6_top
    cmp ebx, 6
    je ok_6
    or edi, 1 << 6
ok_6:

    ; ---- case 3: crossing store, second half patches the target ----
    mov ecx, 4
    xor ebx, ebx
    mov edx, 0x00b89090              ; nop, nop, B8 (mov eax), imm low byte
    jmp c3_pre
    align 16
    times 14 nop
c3_pre:
    nop
    nop
c3_top:                              ; 16-byte aligned (c3_pre = top - 2)
    mov eax, 0
    add ebx, eax
    add edx, 0x01000000
    mov [CODE_BASE + c3_top - 2], edx
    dec ecx
    jnz c3_top
    cmp ebx, 6
    je ok_3
    or edi, 1 << 3
ok_3:

    ; ---- case 4: store through a linear alias of the code page ----
    mov ecx, 4
    xor ebx, ebx
    xor edx, edx
    jmp c4_top
    align 16
c4_top:
    mov eax, 0
    add ebx, eax
    inc edx
    mov [ALIAS + CODE_BASE + c4_top + 1], edx
    dec ecx
    jnz c4_top
    cmp ebx, 6
    je ok_4
    or edi, 1 << 4
ok_4:

    test edi, edi
    jnz fail
    mov al, 1
    out 0xe0, al
    hlt

fail:
    mov eax, edi                     ; failing-case bitmask
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
