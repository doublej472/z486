; lock_rep_ud - LOCK on a string instruction raises #UD with or without REP
;
; Intel486 PRM, LOCK: "#UD if the LOCK prefix is used with an instruction not
; listed" - the string instructions are not lockable, so LOCK REP MOVS/STOS/
; CMPS/SCAS/LODS/INS/OUTS raise interrupt 6 whichever order the LOCK and REP
; prefixes take.  A lockable instruction keeps executing with a stray REP.
; Each slot records the vector (+1, 0 = none) at RES+n; port 0xE4 reports
; (n << 8) | got for every mismatch.
BITS 16
ORG 0
RES equ 0x0900
CUR equ 0x08f0
%macro SLOT 3            ; n, expected (vector+1 or 0), instruction bytes...
    mov word [CUR], %1
    mov byte [EXP + %1], %2
    mov word [CONT + %1*2], %%c
    db %3
%%c:
%endmacro

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7000
    mov word [6*4], ud_handler
    mov word [6*4+2], cs
    mov word [13*4], gp_handler
    mov word [13*4+2], cs
    mov di, RES
    mov cx, 32
    xor al, al
    push ds
    pop es
    rep stosb
    mov word [0x0a00], 0x1234
    SLOT 0, 7, {0xf0, 0xf3, 0xa4}               ; lock rep movsb
    SLOT 1, 7, {0xf3, 0xf0, 0xa4}               ; rep lock movsb
    SLOT 2, 7, {0xf0, 0xf2, 0xae}               ; lock repne scasb
    SLOT 3, 7, {0xf2, 0xf0, 0x66, 0xa7}         ; repne lock cmpsd
    SLOT 4, 7, {0x66, 0xf0, 0xf3, 0xab}         ; lock rep stosd
    SLOT 5, 7, {0xf0, 0xf3, 0x67, 0xac}         ; lock rep lodsb (a32)
    SLOT 6, 7, {0xf0, 0xf3, 0x6c}               ; lock rep insb
    SLOT 7, 7, {0xf3, 0xf0, 0x6e}               ; rep lock outsb
    SLOT 8, 7, {0xf0, 0xa4}                     ; lock movsb
    SLOT 9, 0, {0xf3, 0xf0, 0x01, 0x06, 0x00, 0x0a} ; rep lock add [0a00h],ax
    SLOT 10, 0, {0xf0, 0xf3, 0x87, 0x06, 0x02, 0x0a} ; lock rep xchg [0a02h],ax
    xor cx, cx                  ; no element may run in any #UD slot
    xor si, si
    xor bx, bx
chk:
    mov al, [RES + si]
    cmp al, [EXP + si]
    je .n
    inc bx
    mov dx, si
    shl edx, 8
    or dl, al
    mov eax, edx
    out 0xe4, eax
.n:
    inc si
    cmp si, 11
    jb chk
    test bx, bx
    jnz bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov al, 0xff
    out 0xe0, al
    hlt

ud_handler:
    mov bl, 7
    jmp rec
gp_handler:
    mov bl, 14
rec:
    mov si, [CUR]
    mov [RES + si], bl
    add si, si
    mov ax, [CONT + si]
    mov bp, sp
    mov [bp], ax
    iret

align 2
CONT: times 16 dw 0
EXP:  times 16 db 0
