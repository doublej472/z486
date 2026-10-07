; rmw_read_forms - every RMW form reads its operand exactly once
;
; The counted dword 0x9000 is never cached: phase 1 marks its page PCD (CR0.CD
; clear), phase 2 sets CR0.CD.  Every RMW form below (ALU r/m,reg; ALU
; r/m,imm; INC/DEC/NOT/NEG; byte/word/dword; segment, operand-size and LOCK
; prefixes; XCHG; a dword-crossing operand) touches 0x9000 once, and a 486
; issues one read (and one write) per RMW, so the bench expects
; 2 * FORMS reads of the dword (+count_rd=9000).  The final values are
; checked too.  Port 0xE4 on failure: the value of [0x9000].
BITS 32
ORG 0
PTE_9000 equ 0x1000 + 9*4             ; page tables: directory at 0, table at 0x1000

%macro FORMS 0
    mov dword [0x9000], 0
    mov ecx, 1
    add [0x9000], ecx                  ; 01 /r            -> 1
    add byte [0x9001], cl              ; 00 /r            -> 0x101
    o16 add [0x9002], cx               ; 66 01 /r         -> 0x10101
    or [es:0x9000], ecx                ; 26 09 /r         -> 0x10101
    adc [0x9000], ecx                  ; 11 /r (CF=0)     -> 0x10102
    sub [0x9000], ecx                  ; 29 /r            -> 0x10101
    xor [0x9000], ecx                  ; 31 /r            -> 0x10100
    and [0x9000], ecx                  ; 21 /r            -> 0
    inc dword [0x9000]                 ; FF /0            -> 1
    inc byte [0x9000]                  ; FE /0            -> 2
    o16 dec word [0x9000]              ; 66 FF /1         -> 1
    not dword [0x9000]                 ; F7 /2            -> ~1
    not byte [0x9003]                  ; F6 /2            -> 0x00fffffe
    neg dword [0x9000]                 ; F7 /3            -> 0xff000002
    add dword [0x9000], 5              ; 83 /0            -> 0xff000007
    sub dword [0x9000], 0x7f000000     ; 81 /5            -> 0x80000007
    or byte [0x9000], 0x10             ; 80 /1            -> 0x80000017
    lock add [0x9000], ecx             ; F0 01 /r         -> 0x80000018
    lock inc dword [0x9000]            ; F0 FF /0         -> 0x80000019
    lock not byte [0x9000]             ; F0 F6 /2         -> 0x800000e6
    lock add dword [0x9000], 2         ; F0 83 /0         -> 0x800000e8
    mov edx, 0x18
    xchg [0x9000], edx                 ; 87 /r            -> 0x18
    add [0x8ffe], ecx                  ; dword crossing into 0x9000 (once)
%endmacro
NFORMS equ 23

start:
    mov esp, 0x8000
    ; phase 1: page 0x9000 PCD, caches on
    or dword [PTE_9000], 0x10
    mov eax, 0x9000
    invlpg [eax]
    FORMS
    cmp dword [0x9000], 0x18
    jne fail
    cmp edx, 0x800000e8
    jne fail
    ; phase 2: CR0.CD=1, page cacheable
    and dword [PTE_9000], ~0x10
    mov eax, 0x9000
    invlpg [eax]
    mov eax, cr0
    or eax, 0x40000000
    mov cr0, eax
    FORMS
    cmp dword [0x9000], 0x18
    jne fail
    cmp edx, 0x800000e8
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, [0x9000]
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
