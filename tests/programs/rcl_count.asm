; rcl_count.asm - RCL/RCR counts above the width must rotate the carry ring by
; count mod (width+1). Regression pin (passes on HEAD).
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    mov esp, 0x0003F000
    xor edi, edi
%assign BITN 0

; op, reg, dst, cf_in(0/1), count, expected_combined
; expected_combined = rotated_result | (expected_CF << 16)
%macro RCHECK 6
    mov %2, %3
    %if %4
    stc
    %else
    clc
    %endif
    mov cl, %5
    %1 %2, cl
    movzx ebx, %2
    setc dl
    movzx ecx, dl
    shl ecx, 16
    mov eax, ebx
    or eax, ecx
    cmp eax, %6
    je %%ok
    or  edi, (1 << BITN)
    out DATA_PORT, eax
%%ok:
%assign BITN BITN + 1
%endmacro

;--- byte, CL=9  (9 mod 9 = 0: result and CF unchanged)
    RCHECK rcl, al, 0x81, 0, 9, 0x00000081
    RCHECK rcl, al, 0x81, 1, 9, 0x00010081
    RCHECK rcr, al, 0x81, 0, 9, 0x00000081
    RCHECK rcr, al, 0x81, 1, 9, 0x00010081
;--- byte, CL=10 (10 mod 9 = 1: one CF-ring step)
    RCHECK rcl, al, 0x81, 0, 10, 0x00010002
    RCHECK rcr, al, 0x81, 0, 10, 0x00010040
    RCHECK rcl, al, 0x81, 1, 10, 0x00010003
    RCHECK rcr, al, 0x81, 1, 10, 0x000100c0
;--- byte, CL=12 (12 mod 9 = 3)
    RCHECK rcl, al, 0x81, 0, 12, 0x0000000a
    RCHECK rcr, al, 0x81, 0, 12, 0x00000050
;--- byte, CL=17 (17 mod 9 = 8)
    RCHECK rcl, al, 0x81, 0, 17, 0x00010040
    RCHECK rcr, al, 0x81, 0, 17, 0x00010002
;--- word, CL=17 (17 mod 17 = 0)
    RCHECK rcl, ax, 0x8181, 0, 17, 0x00008181
    RCHECK rcl, ax, 0x8181, 1, 17, 0x00018181
    RCHECK rcr, ax, 0x8181, 1, 17, 0x00018181
;--- word, CL=18 (18 mod 17 = 1)
    RCHECK rcl, ax, 0x8181, 0, 18, 0x00010302
    RCHECK rcr, ax, 0x8181, 0, 18, 0x000140c0

    test edi, edi
    jz  .pass
    mov eax, edi
    out DATA_PORT, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

.pass:
    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
