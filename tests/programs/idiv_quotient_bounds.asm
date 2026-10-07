; idiv_quotient_bounds.asm - IDIV signed-quotient range at every width.
;
; Intel486 PRM, IDIV: "#DE if the quotient is too large for the designated
; register".  The signed range is asymmetric, so the most negative quotient
; (-80h, -8000h, -80000000h) is a valid result while +80h, +8000h and
; +80000000h overflow.  Each width checks:
;   - a valid -max-1 quotient from a positive and from a negative dividend,
;     with its remainder;
;   - a +max+1 quotient (negative / -1 and positive / 2), which faults and
;     leaves the dividend registers unchanged;
;   - a quotient far below -max-1, which faults (the 80386EX capture in
;     SingleStepTests 67F6.7 idx 375 completes AX=741Eh / CL=98h as
;     AX=1E80h; the 486 quotient -285 does not fit AL).
; The #DE handler counts faults and resumes at [resume]; an unexpected #DE
; reports the case number with bit 7 set.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

%macro EXPECT_DE 1              ; next IDIV must fault, resume at %1
    mov word [cs:resume], %1
%endmacro

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0x0F00
    xor ax, ax
    mov es, ax
    mov word [es:0x00], de_handler
    mov [es:0x02], cs
    mov word [de_count], 0
    mov word [resume], unexpected_de

    ;=== byte: AX / r/m8 -> AL quotient, AH remainder ===
    mov bl, 1
    mov ax, 0xFF00              ; -256 / 2 = -128 r 0
    mov cl, 2
    idiv cl
    cmp ax, 0x0080
    jne fail
    inc bl
    mov ax, 0x0080              ; 128 / -1 = -128 r 0
    mov cl, 0xFF
    idiv cl
    cmp ax, 0x0080
    jne fail
    inc bl
    mov ax, 0xFE7F              ; -385 / 3 = -128 r -1
    mov byte [mem8], 3
    idiv byte [mem8]
    cmp ax, 0xFF80
    jne fail
    inc bl
    mov ax, 0x017F              ; 383 / -3 = -127 r 2
    mov cl, 0xFD
    idiv cl
    cmp ax, 0x0281
    jne fail
    inc bl                      ; 5: -128 / -1 = +128 -> #DE
    EXPECT_DE .b5
    mov ax, 0xFF80
    mov cl, 0xFF
    idiv cl
    jmp fail
.b5:
    cmp ax, 0xFF80
    jne fail
    inc bl                      ; 6: 256 / 2 = +128 -> #DE
    EXPECT_DE .b6
    mov ax, 0x0100
    mov byte [mem8], 2
    idiv byte [mem8]
    jmp fail
.b6:
    cmp ax, 0x0100
    jne fail
    inc bl                      ; 7: 29726 / -104 = -285 -> #DE
    EXPECT_DE .b7
    mov ax, 0x741E
    mov cl, 0x98
    idiv cl
    jmp fail
.b7:
    cmp ax, 0x741E
    jne fail
    inc bl                      ; 8: -258 / 2 = -129 -> #DE
    EXPECT_DE .b8
    mov ax, 0xFEFE
    mov cl, 2
    idiv cl
    jmp fail
.b8:
    cmp ax, 0xFEFE
    jne fail
    cmp word [de_count], 4
    jne fail

    ;=== word: DX:AX / r/m16 ===
    mov bl, 0x11
    mov dx, 0xFFFF              ; -65536 / 2 = -32768 r 0
    xor ax, ax
    mov cx, 2
    idiv cx
    cmp ax, 0x8000
    jne fail
    test dx, dx
    jne fail
    inc bl
    xor dx, dx                  ; 32768 / -1 = -32768
    mov ax, 0x8000
    mov word [mem16], 0xFFFF
    idiv word [mem16]
    cmp ax, 0x8000
    jne fail
    test dx, dx
    jne fail
    inc bl                      ; 13: -32768 / -1 = +32768 -> #DE
    EXPECT_DE .w3
    mov dx, 0xFFFF
    mov ax, 0x8000
    mov cx, 0xFFFF
    idiv cx
    jmp fail
.w3:
    cmp dx, 0xFFFF
    jne fail
    cmp ax, 0x8000
    jne fail
    inc bl                      ; 14: 65536 / 2 = +32768 -> #DE
    EXPECT_DE .w4
    mov dx, 1
    xor ax, ax
    mov cx, 2
    idiv cx
    jmp fail
.w4:
    cmp dx, 1
    jne fail
    test ax, ax
    jne fail
    cmp word [de_count], 6
    jne fail

    ;=== dword: EDX:EAX / r/m32 ===
    mov bl, 0x21
    mov edx, 0xFFFFFFFF         ; -2^32 / 2 = -2^31 r 0
    xor eax, eax
    mov ecx, 2
    idiv ecx
    cmp eax, 0x80000000
    jne fail
    test edx, edx
    jne fail
    inc bl
    xor edx, edx                ; 2^31 / -1 = -2^31
    mov eax, 0x80000000
    mov dword [mem32], 0xFFFFFFFF
    idiv dword [mem32]
    cmp eax, 0x80000000
    jne fail
    test edx, edx
    jne fail
    inc bl                      ; 0x23: -2^31 / -1 = +2^31 -> #DE
    EXPECT_DE .d3
    mov edx, 0xFFFFFFFF
    mov eax, 0x80000000
    mov ecx, 0xFFFFFFFF
    idiv ecx
    jmp fail
.d3:
    cmp edx, 0xFFFFFFFF
    jne fail
    cmp eax, 0x80000000
    jne fail
    inc bl                      ; 0x24: 2^32 / 2 = +2^31 -> #DE
    EXPECT_DE .d4
    mov edx, 1
    xor eax, eax
    mov ecx, 2
    idiv ecx
    jmp fail
.d4:
    cmp edx, 1
    jne fail
    test eax, eax
    jne fail
    cmp word [de_count], 8
    jne fail

    mov al, 0x01
    out STATUS_PORT, al
    hlt

unexpected_de:
    or bl, 0x80                 ; a valid quotient raised #DE
fail:
    mov al, bl
    out DATA_PORT, al
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

de_handler:
    push bp
    push si
    mov bp, sp
    mov si, [cs:resume]
    mov [bp+4], si              ; frame IP -> resume point
    mov word [cs:resume], unexpected_de
    inc word [cs:de_count]
    pop si
    pop bp
    iret

align 4
resume:   dw 0
de_count: dw 0
mem8:     db 0
align 2
mem16:    dw 0
align 4
mem32:    dd 0
