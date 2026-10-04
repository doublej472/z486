; shld_overflow.asm - SHLD/SHRD must not inherit a stale shifter `overflow`:
; a wide `shl al,cl` then `shld`/`shrd` must return the double-precision shift,
; not 0.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

DST   equ 0x12345678
SRC   equ 0x9ABCDEF0

; Hand-computed double-precision results (Intel SHLD/SHRD, 32-bit).
;   shld(DST,SRC,3) = DST<<3 | SRC>>29 = 0x91A2B3C4
;   shrd(DST,SRC,3) = DST>>3 | SRC<<29 = 0x02468ACF
;   shld(DST,SRC,5) = DST<<5 | SRC>>27 = 0x468ACF13
;   shrd(DST,SRC,5) = DST>>5 | SRC<<27 = 0x8091A2B3

start:
    mov esp, 0x0003F000
    xor edi, edi

;--- 1: SHLD after a count>=width SHL (stale overflow poisons the result)
    mov eax, DST
    mov ebx, SRC
    mov cl, 8
    shl al, cl                  ; cl>=8: sets shifter overflow=1
    mov eax, DST                ; reload dst; shl al,cl zeroed AL
    mov cl, 3
    shld eax, ebx, cl
    cmp eax, 0x91A2B3C4
    je  .c1
    or  edi, 0x01
    out DATA_PORT, eax          ; observed (wrong) SHLD result
.c1:

;--- 2: SHRD after a count>=width SHL
    mov eax, DST
    mov ebx, SRC
    mov cl, 8
    shl al, cl                  ; cl>=8: sets shifter overflow=1
    mov eax, DST                ; reload dst; shl al,cl zeroed AL
    mov cl, 3
    shrd eax, ebx, cl
    cmp eax, 0x02468ACF
    je  .c2
    or  edi, 0x02
    out DATA_PORT, eax          ; observed (wrong) SHRD result
.c2:

;--- 3 control: SHLD after a narrow SHL (overflow cleared by that shift)
    mov eax, DST
    mov ebx, SRC
    mov cl, 5
    shl al, cl                  ; cl<8: overflow<=0 (and AL is clobbered)
    mov eax, DST                ; reload dst; MOV does not touch the shifter
    mov cl, 5
    shld eax, ebx, cl
    cmp eax, 0x468ACF13
    je  .c3
    or  edi, 0x04
    out DATA_PORT, eax
.c3:

;--- 4 control: SHRD after a narrow SHL
    mov eax, DST
    mov ebx, SRC
    mov cl, 5
    shl al, cl
    mov eax, DST
    mov cl, 5
    shrd eax, ebx, cl
    cmp eax, 0x8091A2B3
    je  .c4
    or  edi, 0x08
    out DATA_PORT, eax
.c4:

    test edi, edi
    jz  .pass
    mov eax, edi
    out DATA_PORT, eax          ; failing-check mask (0x03 expected on HEAD)
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

.pass:
    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
