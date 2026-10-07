; smc_spec_buffer_rm - real-mode self-modifying loop through an RMW store
;
; A DOS-style loop patches the imm16 of "mov ax, imm16" at its own branch
; target with ADD [cs:x], reg or INC word [cs:x], then branches back.  A 486
; must execute the patched code on every iteration: sum 0+1+2+3 = 6.
; Failure data = bitmask of failing cases (bit 1: ADD m,r; bit 2: INC m;
; bit 3: control MOV m,r).
BITS 16
ORG 0
start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    xor di, di

    ; case 1: ADD [cs:imm], si
    mov si, 1
    mov cx, 4
    xor bx, bx
    jmp c1_top
    align 16
c1_top:
    nop
    mov ax, 0                 ; B8 iw, imm16 at c1_top + 2 (no dword crossing)
    add bx, ax
    add [cs:c1_top + 2], si
    dec cx
    jnz c1_top
    cmp bx, 6
    je ok1
    or di, 2
ok1:
    ; case 2: INC word [cs:imm]
    mov cx, 4
    xor bx, bx
    jmp c2_top
    align 16
c2_top:
    nop
    mov ax, 0
    add bx, ax
    inc word [cs:c2_top + 2]
    dec cx
    jnz c2_top
    cmp bx, 6
    je ok2
    or di, 4
ok2:
    ; case 3 (control): MOV [cs:imm], dx
    mov cx, 4
    xor bx, bx
    xor dx, dx
    jmp c3_top
    align 16
c3_top:
    nop
    mov ax, 0
    add bx, ax
    inc dx
    mov [cs:c3_top + 2], dx
    dec cx
    jnz c3_top
    cmp bx, 6
    je ok3
    or di, 8
ok3:
    test di, di
    jnz fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    movzx eax, di
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
