; smc_icache_patch_race.asm - self-modifying code through a warm I-cache
; (found by differential fuzzing with injection)
;
; A store into cached code invalidates the I-cache line one cycle after the
; store's patch. A fetch accepted in that cycle reads the tag on the edge the
; invalidation writes it, so it must not hit the old line. Each case patches
; the immediate of an upcoming MOV, jumps to flush the prefetch queue and
; checks the new value; the padding before the jump varies the timing. The
; second pass runs with the code lines cached.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
CODE_BASE   equ 0x10000

start:
    mov esp, 0x3F000
    mov ebx, 0x11110000                 ; pass tag in the high half
again:
%assign i 0
%rep 12
    lea eax, [ebx + i]
    mov [CODE_BASE + smc_%+i + 1], eax
    times i nop
    jmp short $+2
smc_%+i:
    mov esi, 0
    cmp esi, eax
    jne fail
%assign i i+1
%endrep
    add ebx, 0x11110000
    cmp ebx, 0x33330000
    jne again

    mov al, 0x01
    out STATUS_PORT, al
    hlt

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
