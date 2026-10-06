; ud_realmode - protected-mode-only instructions raise #UD in real mode
;
; Intel486 PRM instruction pages, "Real Address Mode Exceptions": LAR, LSL,
; VERR, VERW, SLDT, STR, LLDT, LTR and ARPL raise interrupt 6; so do the
; removed/absent 0F encodings.  SGDT/SIDT/LGDT/LIDT/SMSW/LMSW, CLTS, INVLPG,
; MOV CRn/DRn and the 486 additions execute.  Each slot records the vector
; (+1, 0 = none) at RES+n; port 0xE4 reports (n << 8) | got for mismatches.
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
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7000
    mov word [6*4], ud_handler
    mov word [6*4+2], 0x1000
    mov word [13*4], gp_handler
    mov word [13*4+2], 0x1000
    mov di, RES
    mov cx, 64
    xor al, al
    push ds
    pop es
    rep stosb
    mov ax, 0x10
    SLOT 0, 7, {0x0f, 0x02, 0xc0}       ; LAR
    SLOT 1, 7, {0x0f, 0x03, 0xc0}       ; LSL
    SLOT 2, 7, {0x0f, 0x00, 0xe0}       ; VERR
    SLOT 3, 7, {0x0f, 0x00, 0xe8}       ; VERW
    SLOT 4, 7, {0x0f, 0x00, 0xc0}       ; SLDT
    SLOT 5, 7, {0x0f, 0x00, 0xc8}       ; STR
    SLOT 6, 7, {0x0f, 0x00, 0xd0}       ; LLDT
    SLOT 7, 7, {0x0f, 0x00, 0xd8}       ; LTR
    SLOT 8, 7, {0x63, 0xc0}             ; ARPL
    SLOT 9, 0, {0x0f, 0x01, 0xe0}       ; SMSW ax
    SLOT 10, 0, {0x0f, 0x06}            ; CLTS
    SLOT 11, 0, {0x0f, 0x20, 0xc0}      ; MOV eax,CR0
    SLOT 12, 0, {0x0f, 0x21, 0xf8}      ; MOV eax,DR7
    SLOT 13, 7, {0x0f, 0x07}            ; LOADALL
    SLOT 14, 7, {0x0f, 0x05}            ; 286 LOADALL
    SLOT 15, 7, {0x0f, 0xa2}            ; CPUID
    SLOT 16, 7, {0x0f, 0x0b}            ; UD2
    SLOT 17, 0, {0x0f, 0xc8}            ; BSWAP eax
    SLOT 18, 0, {0x0f, 0x01, 0x3e, 0x00, 0x60} ; INVLPG [0x6000]
    SLOT 19, 7, {0x0f, 0x22, 0xe0}      ; MOV CR4,eax
    SLOT 20, 7, {0x0f, 0x01, 0xc0}      ; SGDT reg
    xor si, si
    xor bx, bx
chk:
    mov al, [RES + si]
    cmp al, [EXP + si]
    je .n
    inc bx
    mov ah, 0
    mov dx, si
    shl edx, 8
    or dl, al
    mov eax, edx
    out 0xe4, eax
.n:
    inc si
    cmp si, 21
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
    mov ax, 0x10
    iret

align 2
CONT: times 32 dw 0
EXP:  times 32 db 0
