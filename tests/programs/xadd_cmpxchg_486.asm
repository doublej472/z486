; xadd_cmpxchg_486.asm - 486 XADD, CMPXCHG, INVD and WBINVD
;
; Register and memory forms at byte, word and dword width, with LOCK on the
; memory forms and operands that alias. Expected flags come from the
; equivalent ADD or CMP on copies of the operands.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CODE_BASE   equ 0x10000
FLAG_MASK   equ 0x8D5                   ; OF SF ZF AF PF CF

%macro FLAGS_TO 1
    pushfd
    pop %1
    and %1, FLAG_MASK
%endmacro

%macro CHECK 3                          ; reg/mem, expected, case
    cmp %1, %2
    jne fail_%3
%endmacro

start:
    mov esp, 0x3F000
    mov ebp, CODE_BASE + data

    ; 1: XADD r32, r32
    mov ecx, 5
    mov edx, 0xfffffffd
    mov eax, ecx
    add eax, edx
    FLAGS_TO edi
    xadd ecx, edx
    FLAGS_TO esi
    CHECK ecx, 2, 1
    CHECK edx, 5, 1
    CHECK esi, edi, 1

    ; 2: XADD with one register leaves the sum
    mov eax, 0x40000000
    xadd eax, eax
    CHECK eax, 0x80000000, 2

    ; 3: XADD r8, r8 with a high-byte register
    mov ecx, 0x123456f0
    mov edx, 0xabcd20ef
    mov al, 0xf0
    add al, 0x20
    FLAGS_TO edi
    xadd cl, dh
    FLAGS_TO esi
    CHECK ecx, 0x12345610, 3
    CHECK edx, 0xabcdf0ef, 3
    CHECK esi, edi, 3

    ; 4: XADD m16, r16
    mov word [ebp + w0 - data], 0x7fff
    mov ebx, 0x55550001
    mov ax, 0x7fff
    add ax, 1
    FLAGS_TO edi
    xadd word [ebp + w0 - data], bx
    FLAGS_TO esi
    CHECK word [ebp + w0 - data], 0x8000, 4
    CHECK ebx, 0x55557fff, 4
    CHECK esi, edi, 4

    ; 5: LOCK XADD m32, r32
    mov dword [ebp + d0 - data], 0x11111111
    mov esi, 0x22222222
    lock xadd [ebp + d0 - data], esi
    CHECK dword [ebp + d0 - data], 0x33333333, 5
    CHECK esi, 0x11111111, 5

    ; 6: XADD m8, r8
    mov byte [ebp + b0 - data], 0x80
    mov ecx, 0x00000080
    xadd [ebp + b0 - data], cl
    FLAGS_TO esi
    CHECK byte [ebp + b0 - data], 0, 6
    CHECK ecx, 0x80, 6
    mov edi, 0x845                      ; OF ZF PF CF
    CHECK esi, edi, 6

    ; 7: CMPXCHG r32, r32, equal
    mov eax, 7
    mov ecx, 7
    mov edx, 9
    cmpxchg ecx, edx
    FLAGS_TO esi
    CHECK ecx, 9, 7
    CHECK eax, 7, 7
    CHECK esi, 0x44, 7                  ; ZF PF

    ; 8: CMPXCHG r32, r32, not equal
    mov eax, 7
    mov ecx, 8
    mov edx, 9
    mov ebx, eax
    cmp ebx, ecx
    FLAGS_TO edi
    cmpxchg ecx, edx
    FLAGS_TO esi
    CHECK eax, 8, 8
    CHECK ecx, 8, 8
    CHECK edx, 9, 8
    CHECK esi, edi, 8

    ; 9: CMPXCHG with the accumulator as destination is always equal
    mov eax, 0x1234
    mov ecx, 0x5678
    cmpxchg eax, ecx
    CHECK eax, 0x5678, 9

    ; 10: CMPXCHG r8 (AL) not equal, high-byte destination
    mov eax, 0xaaaa0011
    mov ebx, 0xbbbb22bb
    mov ecx, 0x33
    cmpxchg bh, cl
    CHECK eax, 0xaaaa0022, 10
    CHECK ebx, 0xbbbb22bb, 10

    ; 11: CMPXCHG m32 equal and not equal, LOCK
    mov dword [ebp + d0 - data], 0x600d
    mov eax, 0x600d
    mov edx, 0xbeef
    lock cmpxchg [ebp + d0 - data], edx
    FLAGS_TO esi
    CHECK dword [ebp + d0 - data], 0xbeef, 11
    CHECK eax, 0x600d, 11
    CHECK esi, 0x44, 11
    lock cmpxchg [ebp + d0 - data], edx
    CHECK dword [ebp + d0 - data], 0xbeef, 11
    CHECK eax, 0xbeef, 11

    ; 12: CMPXCHG m16 not equal leaves memory and loads AX
    mov word [ebp + w0 - data], 0x4321
    mov eax, 0x99990001
    mov ecx, 0x7777
    cmpxchg [ebp + w0 - data], cx
    CHECK word [ebp + w0 - data], 0x4321, 12
    CHECK eax, 0x99994321, 12

    ; 13: INVD and WBINVD at CPL 0
    mov dword [ebp + d0 - data], 0x13
    wbinvd
    invd
    CHECK dword [ebp + d0 - data], 0x13, 13

    mov al, 0x01
    out STATUS_PORT, al
    hlt

%assign c 1
%rep 13
fail_%+c:
    mov eax, c
    out DATA_PORT, eax
    jmp fail
%assign c c+1
%endrep

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 4
data:
d0: dd 0
w0: dw 0
b0: db 0

times 0x400 - ($ - $$) db 0
