; flush_async_spec - asynchronous platform flush (DMA terminal count) vs the
; prefetcher's branch-target buffer.
;
; Needs the audit testbench hook: port 0xCC arms a platform cache_flush N
; cycles later and holds the external bus busy (+async_stall) from then on,
; so the flush's store-queue drain (CF_DRAIN) lasts a while.
; The loop's branch target T was changed in memory by DMA (no snoop) before
; the flush.  After the flush completes the loop must run the new code; a
; branch-target line captured from the pre-flush I-cache during the drain
; would keep the old code forever.  Failure data = final EAX.
BITS 32
ORG 0
CODE_BASE equ 0x10000
%macro POKE 2
    mov eax, %1
    out 0xc4, eax
    mov eax, %2
    out 0xc8, eax
%endmacro
start:
    mov esp, 0x8000
    xor edx, edx                      ; pass 0: warm T in the I-cache/buffer
    mov ecx, 8
    jmp T
    align 16
T:
    mov eax, 0x11111111
    add ebx, eax
    mov [0x9000], ecx
    dec ecx
    jnz T
    test edx, edx
    jnz check
    POKE CODE_BASE + T + 1, 0x22222222  ; DMA rewrites the imm32, no snoop
    mov eax, 12
    out 0xcc, eax                     ; flush fires ~30 cycles from now
    mov edx, 1
    mov ecx, 400
    jmp T
check:
    cmp eax, 0x22222222
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
