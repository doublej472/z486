; shifter_stack_flags - shift Z/S/P flags must survive a stack instruction
; chained in the SHIFT2 cycle.  The shifter derives the deferred flags from the
; shared SIGMA register; a successor stack op (RET/PUSH/POP/CALL) writes its new
; SP into SIGMA on the same edge, so the retirement reads the SP instead of the
; barrel result.  Windows 95 VMM's `SHR AH,7 / RET` semaphore wait never saw its
; I/O completion.  Real mode; 8 cases; asserts pass, else 0xFF to 0xE0 and the
; failing case number to 0xE4 (EBP).
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0f00h
    mov word [500h], 1
    mov si, 500h
%macro FAIL_UNLESS 2                    ; condition that means OK, case number
    %1 %%ok
    mov bp, %2
    jmp fail
%%ok:
%endmacro

    ; 0 control: bare SHR AH,7 (no chained stack op) must set ZF
    mov eax, 0c0fc0000h
    shr ah, 7
    FAIL_UNLESS jz, 0

    ; 1: indirect call, callee SHR AH,7 / RET, ZF=1 expected
    push word f_shr_ah
    mov bx, sp
    mov eax, 0c0fc0000h
    call word [bx]
    FAIL_UNLESS jz, 1
    jpe .c1p
    mov bp, 101
    jmp fail
.c1p:
    add sp, 2

    ; 2: memory form as in VMM: MOV AX,[SI] / DEC EAX / SHR AH,7 / RET
    push word f_vmm
    mov bx, sp
    mov eax, 0c0fce300h
    call word [bx]
    FAIL_UNLESS jz, 2
    add sp, 2

    ; 3: SAR AH,1 with AH=80h -> C0h: SF=1 ZF=0, then PUSH
    mov ah, 80h
    sar ah, 1
    push ax
    FAIL_UNLESS js, 3
    FAIL_UNLESS jnz, 4
    pop ax

    ; 5: SHL BX,1 (8000h -> 0, ZF=1) then POP
    push word 1234h
    mov bx, 8000h
    shl bx, 1
    pop cx
    FAIL_UNLESS jz, 5

    ; 6: SHR EDX,31 (7FFFFFFFh -> 0, ZF=1) then CALL
    mov edx, 7fffffffh
    shr edx, 31
    call f_check_zf
    cmp al, 1
    FAIL_UNLESS je, 6

    ; 7: SHR AL,1 (1 -> 0) then RET from a near call
    call f_shr_al
    FAIL_UNLESS jz, 7

    ; 8: nonzero result must clear ZF: SHR AH,1 (AH=2 -> 1) then RET
    push word f_shr_ah1
    mov bx, sp
    mov eax, 0200h
    call word [bx]
    FAIL_UNLESS jnz, 8
    add sp, 2

    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail:
    mov dx, DATA_PORT
    mov ax, bp                    ; failing case number
    out dx, ax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

f_shr_ah:
    shr ah, 7
    ret
f_vmm:
    mov ax, [si]
    dec eax
    shr ah, 7
    ret
f_check_zf:                       ; AL = 1 if ZF was set on entry
    setz al
    ret
f_shr_al:
    mov al, 1
    shr al, 1
    ret
f_shr_ah1:
    shr ah, 1
    ret
