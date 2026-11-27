; de_contributory_df.asm - a divide error is contributory: a contributory
; fault while delivering #DE raises #DF
;
; i486 PRM (1992) 9.9.8 (p. 9-17): "When two contributory events occur, they
; cannot be handled, and a double-fault exception is generated." Table 9-4
; lists Divide Error (0) with 10-13 as Contributory Exceptions, 1-7 and 16
; as benign. "The processor always pushes an error code onto the stack of
; the double-fault handler; however, the error code is always O."
;
; 1. DIV by zero, IDT[0] -> a not-present code segment: #DF(0), not #NP.
; 2. DIV overflow (quotient too large), IDT[0] offset beyond the CS limit
;    (#GP at the transfer): #DF(0).
; 3. 8-bit IDIV by zero, IDT[0] -> not-present: #DF(0).
; 4. Control: #UD (benign), IDT[6] -> the not-present segment: #NP(41h).
; 5. Control: a #DE delivered through a good gate, then the #UD of case 4
;    again: #NP(41h), the completed #DE leaves no contributory mark.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE    equ 0x08
SEL_DATA    equ 0x10
SEL_NP      equ 0x18        ; code, not present
SEL_SHORT   equ 0x20        ; code, limit 0FFFh
STACK_TOP   equ 0x3000

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SEL_CODE:pm_entry

BITS 32
pm_entry:
    mov ax, SEL_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK_TOP

; set up a case: resume at %1 when the handler runs
%macro ARM 1
    mov esp, STACK_TOP
    mov dword [resume], %1
    mov dword [got_vec], 0xFF
    mov dword [got_err], 0xFFFF
%endmacro
; %1 case, %2 expected vector, %3 expected error code
%macro CHECK 3
    mov eax, (%1 << 8) | 1          ; no exception
    jmp fail
.c%1:
    mov esp, STACK_TOP
    cmp dword [got_vec], %2
    mov eax, (%1 << 8) | 2
    jne fail
    cmp dword [got_err], %3
    mov eax, (%1 << 8) | 3
    jne fail
%endmacro

    ; IDT[0] -> not-present segment
    mov word [idt + 0*8 + 2], SEL_NP
    ARM .c1
    xor edx, edx
    xor ecx, ecx
    mov eax, 1
    div ecx
    CHECK 1, 8, 0
    ; IDT[0] -> offset 2000h in a segment of limit 0FFFh
    mov word [idt + 0*8 + 0], 0x2000
    mov word [idt + 0*8 + 2], SEL_SHORT
    ARM .c2
    mov edx, 2
    mov ecx, 1
    xor eax, eax
    div ecx
    CHECK 2, 8, 0
    mov word [idt + 0*8 + 0], isr_de
    mov word [idt + 0*8 + 2], SEL_NP
    ARM .c3
    mov ax, 5
    xor cl, cl
    idiv cl
    CHECK 3, 8, 0
    ARM .c4
    ud2
    CHECK 4, 11, SEL_NP | 1
    mov word [idt + 0*8 + 2], SEL_CODE
    ARM .c5
    xor edx, edx
    xor ecx, ecx
    div ecx
    CHECK 5, 0, 0xFFFF
    ARM .c6
    ud2
    CHECK 6, 11, SEL_NP | 1

    mov al, STATUS_PASS
    out STATUS_PORT, al
    hlt

fail:
    out DATA_PORT, eax
    mov al, STATUS_FAIL
    out STATUS_PORT, al
    hlt

; handlers: record the vector (and the error code where one is pushed)
isr_de:
    mov dword [got_vec], 0
    jmp [resume]
isr_df:
    mov dword [got_vec], 8
    pop dword [got_err]
    jmp [resume]
isr_np:
    mov dword [got_vec], 11
    pop dword [got_err]
    jmp [resume]
isr_gp:
    mov dword [got_vec], 13
    pop dword [got_err]
    jmp [resume]
isr_other:
    mov eax, 0xEEEE
    jmp fail

align 4
resume:     dd 0
got_vec:    dd 0
got_err:    dd 0

;==================================================================
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code
    dq 0x00CF93010000FFFF       ; 0x10 data
    dq 0x00CF1B010000FFFF       ; 0x18 code, P=0
    dq 0x00409B0100000FFF       ; 0x20 code, limit 0FFFh, byte granular
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro GATE 1
    dw %1
    dw SEL_CODE
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
    GATE isr_de                 ; 0
%rep 5
    GATE isr_other              ; 1-5
%endrep
    dw isr_other                ; 6 -> not present (SEL_NP)
    dw SEL_NP
    db 0
    db 10001110b
    dw 0
    GATE isr_other              ; 7
    GATE isr_df                 ; 8
    GATE isr_other              ; 9
    GATE isr_other              ; 10
    GATE isr_np                 ; 11
    GATE isr_other              ; 12
    GATE isr_gp                 ; 13
%rep 18
    GATE isr_other
%endrep
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000
