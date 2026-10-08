; divtest_ref.asm - random DIV r16/r32 and IDIV r32 against an in-assembly
; shift-and-subtract reference that uses NO divide instruction.
;
; Adapted from the Zet98 reference at d4a3789 (tests/hardware/divtest98.asm,
; "DIVTEST.COM [rounds]: random DIV/IDIV against a shift/subtract reference").
; The reference values are computed by ref_udiv (a restoring shift/subtract
; 64/32 unsigned divide) and the signed |a|/|b| + sign-fix, then compared with
; the CPU's DIV/IDIV -- never from this core's RTL, so a divergence is a real
; finding. Quotients that would overflow are skipped (the reference decides),
; so the only #DE path is a CPU bug and is reported as a failure.
;
; Scale is reduced from the DOS original's 8 x 4096 x 3 rounds to 64 x 3 cases
; (still the same xorshift32 stream, deterministic seed 2463534242) so the
; suite's simulation budget stays bounded; the reference loop is unchanged.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    ; IVT[0] = #DE (divide error). The reference skips every overflow case, so
    ; a #DE here is the CPU diverging and must fail the test.
    mov es, ax
    mov word [es:0], de_handler
    mov word [es:2], cs

    mov dword [seed], 2463534242
    mov word [fails], 0

; ---- 64 unsigned 16-bit divisions (DX:AX / r16) ---------------------------
    mov cx, 64
.u16:   push    cx
        call    rnd32
        mov     [dividend], eax
        call    rnd32
        mov     [dividend+4], eax
        call    rnd32
        mov     ecx, eax
        call    rnd32
        and     cl, 15                  ; divisor width 1..16 bits
        inc     cl
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
        and     eax, ebx
        jnz     .u16d
        inc     eax
.u16d:  mov     [divisor], eax
        mov     eax, [dividend]         ; low dword
        movzx   ebx, word [divisor]
        xor     edx, edx
        call    ref_udiv                ; EDX:EAX / EBX -> EAX q, EDX r
        cmp     eax, 0FFFFh
        ja      .u16skip                ; would overflow: #DE on real silicon
        mov     [exp_q], eax
        mov     [exp_r], edx
        mov     ax, [dividend]
        mov     dx, [dividend+2]
        mov     bx, [divisor]
        div     bx
        movzx   eax, ax
        movzx   edx, dx
        mov     byte [kind], 1
        call    compare
.u16skip:
        pop     cx
        dec     cx
        jnz     .u16

; ---- 64 unsigned 32-bit divisions (EDX:EAX / r32) -------------------------
    mov     cx, 64
.u32:   push    cx
        call    rnd32
        mov     [dividend], eax
        call    rnd32
        mov     [dividend+4], eax
        call    rnd32
        mov     ecx, eax
        call    rnd32
        and     cl, 31
        inc     cl
        mov     ebx, 0FFFFFFFFh
        cmp     cl, 32
        je      .full
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
.full:  and     eax, ebx
        jnz     .u32d
        inc     eax
.u32d:  mov     [divisor], eax
        ; high dword below the divisor so the quotient fits (no #DE):
        ; high := high mod divisor, computed by the reference, not by DIV
        mov     eax, [dividend+4]
        xor     edx, edx
        mov     ebx, [divisor]
        call    ref_udiv
        mov     [dividend+4], edx
        mov     eax, [dividend]
        mov     edx, [dividend+4]
        mov     ebx, [divisor]
        call    ref_udiv
        mov     [exp_q], eax
        mov     [exp_r], edx
        mov     eax, [dividend]
        mov     edx, [dividend+4]
        div     dword [divisor]
        mov     byte [kind], 2
        call    compare
        pop     cx
        dec     cx
        jnz     .u32

; ---- 64 signed 32-bit IDIV (EAX / r32, sign-extended into EDX) ------------
    mov     cx, 64
.s32:   push    cx
        call    rnd32
        mov     [dividend], eax
        call    rnd32
        mov     ecx, eax
        call    rnd32
        and     cl, 31
        inc     cl
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
        and     eax, ebx
        jnz     .s32d
        inc     eax
.s32d:  test    ch, 1
        jz      .s32p
        neg     eax
.s32p:  mov     [divisor], eax
        ; reference: |a| / |b| unsigned, then fix signs (truncate toward 0)
        mov     eax, [dividend]
        mov     ebx, [divisor]
        mov     esi, eax
        xor     esi, ebx                ; quotient sign in bit 31
        mov     edi, eax                ; remainder sign = dividend sign
        test    eax, eax
        jns     .a
        neg     eax
.a:     test    ebx, ebx
        jns     .b
        neg     ebx
.b:     xor     edx, edx
        call    ref_udiv
        test    esi, esi
        jns     .qs
        neg     eax
.qs:    test    edi, edi
        jns     .rs
        neg     edx
.rs:    mov     [exp_q], eax
        mov     [exp_r], edx
        mov     eax, [dividend]
        cdq
        idiv    dword [divisor]
        mov     byte [kind], 3
        cmp     dword [dividend], 80000000h ; -2^31 / -1 overflows: skip
        jne     .scmp
        cmp     dword [divisor], -1
        je      .sskip
.scmp:  call    compare
.sskip: pop     cx
        dec     cx
        jnz     .s32

        cmp     word [fails], 0
        jne     fail
        mov     al, STATUS_PASS
        mov     dx, STATUS_PORT
        out     dx, al
        hlt

; ---- shift/subtract reference (no divide instruction) ---------------------
; EDX:EAX / EBX with EDX < EBX (quotient fits 32 bits) -> EAX quotient,
; EDX remainder. Restoring shift/subtract; verbatim from DIVTEST.COM.
ref_udiv:
        push    ecx
        push    esi
        mov     esi, eax
        xor     eax, eax
        mov     cx, 32
.l:     shl     esi, 1
        rcl     edx, 1
        jc      .sub
        cmp     edx, ebx
        jb      .zero
.sub:   sub     edx, ebx
        stc
        rcl     eax, 1
        jmp     .n
.zero:  shl     eax, 1
.n:     loop    .l
        pop     esi
        pop     ecx
        ret

; got quotient EAX / remainder EDX vs exp_q / exp_r
compare:
        cmp     eax, [exp_q]
        jne     .bad
        cmp     edx, [exp_r]
        jne     .bad
        ret
.bad:   inc     word [fails]
        ret

rnd32:  ; xorshift32 (same stream as DIVTEST.COM)
        mov     eax, [seed]
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     [seed], eax
        ret

; unexpected #DE (the reference skips overflow cases): report and fail
de_handler:
        mov     sp, 0x8000
        mov     word [cs:fails], 0xFFFF
        jmp     fail

fail:
        mov     dx, DATA_PORT
        movzx   eax, word [fails]
        movzx   ebx, byte [kind]
        shl     ebx, 16
        or      eax, ebx
        out     dx, eax
        mov     al, STATUS_FAIL
        mov     dx, STATUS_PORT
        out     dx, al
        hlt

seed:    dd 0
fails:   dw 0
kind:    db 0
dividend: dd 0, 0
divisor: dd 0
exp_q:   dd 0
exp_r:   dd 0
