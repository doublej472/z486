; shl1_overflow.asm - OF for 1-bit shifts, checked against the Intel definition
; (SAL/SAR/SHL/SHR):
;   "For left shifts, the OF flag is set to 0 if the most-significant bit of the
;    result is the same as the CF flag ...; otherwise, it is set to 1.
;    For the SAR instruction, the OF flag is cleared for all 1-bit shifts.
;    For the SHR instruction, the OF flag is set to the most-significant bit of
;    the original operand."
; CF is the last bit shifted out.  ZF/SF/PF come from the result; AF is
; undefined for shifts, so the comparison masks to CF|PF|ZF|SF|OF (0x08C5).
;
; Each case does the shift, saves EFLAGS, masks, and compares.  A failure
; reports the case number on port 0xE4 and the masked flags it observed.
BITS 32
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
D1 equ 0x4000
FLAGMASK equ 0x08C5

%macro CASE 3            ; %1 = case number, %2 = setup, %3 = expected masked flags
    %2
    pushfd
    pop eax
    and eax, FLAGMASK
    cmp eax, %3
    je  %%ok
    mov ecx, %1
    jmp fail_flags
%%ok:
%endmacro

start:
    mov esp, 0x3000

    ; 1: shl dword [D1],1  0x80000000 -> 0        CF=1 OF=1 ZF=1 PF=1
    mov dword [D1], 0x80000000
    CASE 1, {shl dword [D1], 1}, 0x0845

    ; 2: shl eax,1         same operation, register form
    mov eax, 0x80000000
    CASE 2, {shl eax, 1}, 0x0845

    ; 3: shl dword [D1],1  0x40000000 -> 0x80000000  CF=0 OF=1 SF=1 PF=1
    mov dword [D1], 0x40000000
    CASE 3, {shl dword [D1], 1}, 0x0884

    ; 4: shl word [D1],1   0x8000 -> 0              CF=1 OF=1 ZF=1 PF=1
    mov word [D1], 0x8000
    CASE 4, {shl word [D1], 1}, 0x0845

    ; 5: shl byte [D1],1   0x80 -> 0                CF=1 OF=1 ZF=1 PF=1
    mov byte [D1], 0x80
    CASE 5, {shl byte [D1], 1}, 0x0845

    ; 6: shl byte [D1],1   0x40 -> 0x80             CF=0 OF=1 SF=1 PF=1
    mov byte [D1], 0x40
    CASE 6, {shl byte [D1], 1}, 0x0880

    ; 7: shr dword [D1],1  0x80000000 -> 0x40000000  CF=0 OF=1 (original MSB)
    mov dword [D1], 0x80000000
    CASE 7, {shr dword [D1], 1}, 0x0804

    ; 8: sar dword [D1],1  0x80000000 -> 0xc0000000  CF=0 OF=0 SF=1 PF=1
    mov dword [D1], 0x80000000
    CASE 8, {sar dword [D1], 1}, 0x0084

    ; 9: shl dword [D1],cl with cl=1 - same rule, count from CL
    mov dword [D1], 0x80000000
    mov cl, 1
    CASE 9, {shl dword [D1], cl}, 0x0845

    ; 10: shl eax,cl with cl=1, register form
    mov eax, 0x80000000
    mov cl, 1
    CASE 10, {shl eax, cl}, 0x0845

    ; 11: rol dword [D1],1 0x80000000 -> 1.  ROL/ROR leave SF/ZF/AF/PF
    ;     unaffected, so set ZF=1 PF=1 SF=0 first and require them to survive;
    ;     CF=1 and OF=1 (CF xor the result's MSB).
    xor eax, eax
    mov dword [D1], 0x80000000
    rol dword [D1], 1
    pushfd
    pop eax
    and eax, FLAGMASK
    cmp eax, 0x0845
    je  case12
    mov ecx, 11
    jmp fail_flags
case12:
    ; 12: ror dword [D1],1 0x00000001 -> 0x80000000, CF=1, OF=1 (the result's
    ;     two MSBs differ), ZF/PF/SF preserved as above.
    xor eax, eax
    mov dword [D1], 0x00000001
    ror dword [D1], 1
    pushfd
    pop eax
    and eax, FLAGMASK
    cmp eax, 0x0845
    je  all_done
    mov ecx, 12
    jmp fail_flags
all_done:

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

; %1 = case number, %2 = the masked flags observed
fail_flags:
    mov dx, DATA_PORT
    out dx, eax                  ; the flags actually seen (masked)
    mov eax, ecx
    mov dx, DATA_PORT
    out dx, eax                  ; the case number
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang
