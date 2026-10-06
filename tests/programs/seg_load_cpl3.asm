; seg_load_cpl3.asm - segment register loads at CPL 3 (i486 PRM 6.3.x)
;
; DS/ES/FS/GS: null is allowed; data or readable code; for data and
; non-conforming code max(CPL, RPL) <= DPL, conforming code unchecked;
; not present -> #NP. SS: RPL = CPL, DPL = CPL, writable data; null ->
; #GP; not present -> #SS.
;
; Each case loads a selector with MOV and records the vector it raised
; (0 if none); the handlers skip the 2-byte MOV. The table of vectors is
; compared with the expected one at the end.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code
; (case << 16 | got << 8 | expected).

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CONF0   equ 0x18    ; conforming readable code, DPL 0
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_CODE3   equ 0x30
SEL_D2      equ 0x38    ; data, DPL 2
SEL_XCODE3  equ 0x40    ; execute-only code, DPL 3
SEL_RCODE3  equ 0x48    ; readable code, DPL 3
SEL_RO3     equ 0x50    ; read-only data, DPL 3
SEL_NP3     equ 0x58    ; data, DPL 3, not present
SEL_D3B     equ 0x60    ; data, DPL 3 (second)

STACK0_TOP  equ 0x3000
STACK3_TOP  equ 0x4000

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm_entry

BITS 32
pm_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword 0x00003002       ; IOPL 3
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

; %1 case, %2 sreg, %3 selector. Results go through GS = DATA3|3.
%macro CASE 3
    mov byte [gs:cur], %1
    mov ax, %3
    mov %2, ax
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov gs, ax
    CASE 0, ds, SEL_D3B             ; RPL 0, DPL 3: ok
    CASE 1, ds, SEL_D2 | 3          ; #GP
    CASE 2, ds, SEL_D2              ; CPL > DPL: #GP
    CASE 3, ds, SEL_CONF0 | 3       ; conforming readable: ok
    CASE 4, es, SEL_CONF0           ; conforming, RPL 0: ok
    CASE 5, ds, SEL_RCODE3 | 3      ; readable code: ok
    CASE 6, ds, SEL_XCODE3 | 3      ; execute-only: #GP
    CASE 7, es, 0                   ; null: ok
    CASE 8, ds, SEL_NP3 | 3         ; not present: #NP
    CASE 9, fs, SEL_RO3 | 3         ; read-only data: ok
    CASE 10, ss, SEL_D3B            ; RPL != CPL: #GP
    CASE 11, ss, SEL_RO3 | 3        ; not writable: #GP
    CASE 12, ss, 0                  ; null: #GP
    CASE 13, ss, SEL_NP3 | 3        ; not present: #SS
    CASE 14, ss, SEL_RCODE3 | 3     ; code: #GP
    CASE 15, ss, SEL_D3B | 3        ; ok
    CASE 16, ss, SEL_D2 | 3         ; DPL != CPL: #GP
    mov byte [gs:cur], 0xFF

    ; compare
    xor esi, esi
.cmp:
    mov al, [gs:got + esi]
    cmp al, [gs:want + esi]
    jne .fail
    inc esi
    cmp esi, NCASE
    jb .cmp
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    jmp $
.fail:
    mov eax, esi
    shl eax, 8
    mov al, [gs:got + esi]
    shl eax, 8
    mov al, [gs:want + esi]
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp $

; Fault handlers: record the vector for the current case, skip the MOV
%macro FH 1
isr_%1:
    push eax
    mov al, %1
    jmp fault_common
%endmacro
FH 0x0B
FH 0x0C
FH 0x0D

fault_common:
    ; [esp]=EAX, +4 err, +8 EIP, +12 CS
    push ds
    push ebx
    mov bx, SEL_DATA0
    mov ds, bx
    movzx ebx, byte [cur]
    cmp ebx, NCASE
    jae .bad
    mov [got + ebx], al
    add dword [esp+16], 2       ; skip MOV sreg, ax
    pop ebx
    pop ds
    pop eax
    add esp, 4
    iretd
.bad:
    shl eax, 8
    mov al, 0xEE
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

;==================================================================
NCASE equ 17
cur:
    db 0
got:
    times NCASE db 0
want:
    db 0, 13, 13, 0, 0, 0, 13, 0, 11, 0
    db 13, 13, 13, 12, 13, 0, 13

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x00CF9F010000FFFF       ; 0x18 conforming readable, DPL 0
    dq 0x00CFF3010000FFFF       ; 0x20 data3
    dw 0x0067                   ; 0x28 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CFFB010000FFFF       ; 0x30 code3
    dq 0x00CFD3010000FFFF       ; 0x38 data, DPL 2
    dq 0x00CFF9010000FFFF       ; 0x40 execute-only code, DPL 3
    dq 0x00CFFB010000FFFF       ; 0x48 readable code, DPL 3
    dq 0x00CFF1010000FFFF       ; 0x50 read-only data, DPL 3
    dq 0x00CF73010000FFFF       ; 0x58 data, DPL 3, not present
    dq 0x00CFF3010000FFFF       ; 0x60 data, DPL 3
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro IG 1
    dw %1
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
    times 0x0B dq 0
    IG isr_0x0B
    IG isr_0x0C
    IG isr_0x0D
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss386:
    dd 0
    dd STACK0_TOP
    dd SEL_DATA0
    times 22 dd 0
    dw 0
    dw 104
