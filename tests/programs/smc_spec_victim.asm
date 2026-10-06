; smc_spec_victim - self-modifying code vs the prefetcher's branch-target
; buffer: the victim line (spec_b) and RMW_FAST stores followed by other
; memory operations (complements smc_spec_buffer)
;
; Each case is a 4-iteration loop that patches the imm32 of the
; "mov eax, imm32" at its own branch target; the sum must be 0+1+2+3 = 6.
;   cases 1-3: the store runs in a second line reached by a JMP, so the loop
;     target sits in the victim slot (spec_b) when it is patched: RMW_FAST
;     ADD m,r (1), INC m (2), WR_FAST MOV (3).
;   cases 4-7: an RMW_FAST store followed at once by a load (4, 5), a store
;     (6) or PUSH/POP (7): the store must be reported with its own line
;     (rmw_fast_phys_r), not whatever address the paging port shows then.
; Failure data = bitmask of failing cases.
BITS 32
ORG 0
CODE_BASE equ 0x10000
ALIAS     equ 0x200000 - CODE_BASE   ; alias linear = ALIAS + CODE_BASE + off

start:
    mov esp, 0x8000
    xor edi, edi                     ; bit n set = case n failed


    ; ---- case 1 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c1_top
    align 16
c1_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c1_top + 4 (aligned)
    add ebx, eax

    jmp c1_mid
    align 16
c1_mid:
    add [CODE_BASE + c1_top + 4], esi  ; RMW_FAST store while c1_top is the victim (spec_b)
    dec ecx
    jnz c1_top
    cmp ebx, 6
    je ok_1
    or edi, 1 << 1
ok_1:

    ; ---- case 2 ----
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

    jmp c2_mid
    align 16
c2_mid:
    inc dword [CODE_BASE + c2_top + 4]   ; rmw-unary-fast, victim line
    dec ecx
    jnz c2_top
    cmp ebx, 6
    je ok_2
    or edi, 1 << 2
ok_2:

    ; ---- case 3 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c3_top
    align 16
c3_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c3_top + 4 (aligned)
    add ebx, eax

    jmp c3_mid
    align 16
c3_mid:
    mov edx, [CODE_BASE + c3_top + 4]
    inc edx
    mov [CODE_BASE + c3_top + 4], edx   ; WR_FAST store, victim line
    dec ecx
    jnz c3_top
    cmp ebx, 6
    je ok_3
    or edi, 1 << 3
ok_3:

    ; ---- case 4 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c4_top
    align 16
c4_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c4_top + 4 (aligned)
    add ebx, eax
    add [CODE_BASE + c4_top + 4], esi
    mov edx, [0x9010]                ; load right behind the RMW_FAST store
    dec ecx
    jnz c4_top
    cmp ebx, 6
    je ok_4
    or edi, 1 << 4
ok_4:

    ; ---- case 5 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c5_top
    align 16
c5_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c5_top + 4 (aligned)
    add ebx, eax
    inc dword [CODE_BASE + c5_top + 4]
    mov edx, [0x9020]
    dec ecx
    jnz c5_top
    cmp ebx, 6
    je ok_5
    or edi, 1 << 5
ok_5:

    ; ---- case 6 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c6_top
    align 16
c6_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c6_top + 4 (aligned)
    add ebx, eax
    add [CODE_BASE + c6_top + 4], esi
    mov [0x9030], edx                ; store right behind the RMW_FAST store
    dec ecx
    jnz c6_top
    cmp ebx, 6
    je ok_6
    or edi, 1 << 6
ok_6:

    ; ---- case 7 ----
    mov esi, 1
    mov ecx, 4
    xor ebx, ebx
    jmp c7_top
    align 16
c7_top:
    nop
    nop
    nop
    mov eax, 0                       ; imm32 at c7_top + 4 (aligned)
    add ebx, eax
    add [CODE_BASE + c7_top + 4], esi
    push edx
    pop edx
    dec ecx
    jnz c7_top
    cmp ebx, 6
    je ok_7
    or edi, 1 << 7
ok_7:

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
