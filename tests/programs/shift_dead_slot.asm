; shift_dead_slot.asm - fast-path shift hazards found by differential fuzzing
;
; 1-3: a shift's deferred SF/ZF/PF must not come from SIGMA: a PUSH or CALL
;      issued into the shift's dead slot writes its ESP update there on the
;      same edge. Each shift is preceded by XOR (ZF=PF=1), so stale or
;      ESP-derived flags differ from the expected value.
; 4:   SHRD captures its register operand one cycle ahead; a preceding ROR's
;      deferred result landing on that edge must be seen.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
FLAG_MASK   equ 0x0C5               ; SF ZF PF CF

start:
    mov esp, 0x3F000

    ; 1: SAR, PUSH imm, PUSHFD
    mov edx, 0xce1572bd
    xor eax, eax
    sar edx, 1
    push 0xc3161ac4
    pushfd
    pop eax
    add esp, 4
    and eax, FLAG_MASK
    cmp eax, 0x81
    jne fail1
    cmp edx, 0xe70ab95e
    jne fail1

    ; 2: SHLD, PUSH r, PUSHFD
    mov ebx, 0x723d2169
    mov edx, 0xfa065691
    xor eax, eax
    shld ebx, edx, 18
    push eax
    pushfd
    pop eax
    add esp, 4
    and eax, FLAG_MASK
    cmp eax, 0x80
    jne fail2
    cmp ebx, 0x85a7e819
    jne fail2

    ; 3: SHL CL, CALL, PUSHFD in the callee
    mov edx, 0x13579bdf
    mov ecx, 5
    xor eax, eax
    shl edx, cl
    call flags_in_callee
    and eax, FLAG_MASK
    cmp eax, 0x00
    jne fail3
    cmp edx, 0x6af37be0
    jne fail3

    ; 4: ROR, then SHRD reading the rotated register
    mov esi, 0x12f31fe2
    ror si, 17
    shrd esi, esi, 24
    cmp esi, 0xf30ff112
    jne fail4

    mov al, 0x01
    out STATUS_PORT, al
    hlt

flags_in_callee:
    pushfd
    pop eax
    ret

fail1: mov ebx, 1
    jmp fail
fail2: mov ebx, 2
    jmp fail
fail3: mov ebx, 3
    jmp fail
fail4: mov ebx, 4
fail:
    shl ebx, 16
    or eax, ebx
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
