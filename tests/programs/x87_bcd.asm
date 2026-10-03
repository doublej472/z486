; x87_bcd.asm - FBSTP packed-BCD stores: digit boundaries, 18-digit values,
; signs, rounding of non-integers, and the out-of-range indefinite.
; The x87 keeps a 53-bit significand internally, so the 18-digit cases use
; integers that are exact in 53 bits.

BITS 16
org 0

STATUS_PORT equ 0xE0
STATUS_PASS equ 0x01

; FILD qword, FBSTP, compare the ten stored bytes with the expected image.
%macro bcd_int 1
    inc bl
    fild qword [%1]
    fbstp tword [out]
    mov si, out
    mov di, %1 + 8
    mov cx, 10
    repe cmpsb
    jne fail
%endmacro

%macro bcd_real 1
    inc bl
    fld qword [%1]
    fbstp tword [out]
    mov si, out
    mov di, %1 + 8
    mov cx, 10
    repe cmpsb
    jne fail
%endmacro

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x700

    xor bx, bx                          ; BL = case number reported on failure.
    fninit                              ; Round to nearest, exceptions masked.
    bcd_int case_zero
    bcd_int case_one
    bcd_int case_max
    bcd_int case_digits
    bcd_int case_negative
    bcd_int case_power
    bcd_real case_half_even
    bcd_real case_negative_half

    ; Out of range: the masked invalid result is the BCD indefinite.
    fnclex
    bcd_int case_range
    fnstsw ax
    test al, 0x01                       ; IE
    jz fail
    fnclex

    fnstsw ax                           ; Stack must be empty again.
    and ax, 0x3800
    jnz fail

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

fail:
    mov al, bl
    or al, 0x80
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 4
out:                times 10 db 0xee
; Each case: the source (qword integer or real), then the expected ten bytes.
case_zero:          dq 0
                    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
case_one:           dq 1
                    db 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
case_max:           dq 999999999999999872
                    db 0x72, 0x98, 0x99, 0x99, 0x99, 0x99, 0x99, 0x99, 0x99, 0x00
case_digits:        dq 123456789012345664
                    db 0x64, 0x56, 0x34, 0x12, 0x90, 0x78, 0x56, 0x34, 0x12, 0x00
case_negative:      dq -987654321098765312
                    db 0x12, 0x53, 0x76, 0x98, 0x10, 0x32, 0x54, 0x76, 0x98, 0x80
case_power:         dq 100000000000000000
                    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00
case_half_even:     dq 0x4004000000000000   ; 2.5 rounds to 2
                    db 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
case_negative_half: dq 0xc00c000000000000   ; -3.5 rounds to -4
                    db 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
case_range:         dq 1000000000000000000
                    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0xff, 0xff
