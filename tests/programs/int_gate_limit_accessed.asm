; int_gate_limit_accessed.asm - an INT n whose gate offset is beyond the
; target code segment's limit leaves that descriptor's Accessed bit clear
;
; i486 PRM (1992) INT n (p. 26-167, 26-168): "Instruction pointer must be
; within CS segment boundaries else #GP(O)" comes before "Load CS descriptor
; into invisible portion of CS register" (inner level) and before the pushes
; and the CS:EIP load (same level).  5.1.3.1: the processor sets the
; Accessed bit when the segment is accessed, i.e. loaded; a faulting INT
; loads no CS.
;
; Selector 18h and 28h: code DPL 0, limit 1FFFh, Accessed clear.  Cases:
;   1  INT 40h (32-bit interrupt gate -> 18h:3000h) at CPL 0: #GP(0) at the
;      INT, 18h A still clear
;   2  INT 41h (16-bit interrupt gate -> 18h:3000h): the same
;   3  #UD through IDT[6] (32-bit trap gate -> 18h:3000h): #GP(0), A clear
;   4  INT 43h from ring 3 (DPL 3 gate -> 18h:3000h, inner level): #GP(0),
;      A clear
;   5  far CALL through a call gate (40h -> 18h:3000h): #GP(0), A clear
;   6  far JMP through that call gate: #GP(0), A clear
;   7  controls, offsets within the limit: INT 42h -> 28h (same level), INT
;      44h from ring 3 -> 48h (inner level, before case 4's INT), far CALL
;      through call gate 50h -> 58h: each runs and sets its target's A
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4
; (case << 8) | check.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_LIM     equ 0x18
SEL_CODE3   equ 0x20
SEL_LIM2    equ 0x28
SEL_DATA3   equ 0x30
SEL_TSS     equ 0x38
SEL_CGATE   equ 0x40
SEL_LIM3    equ 0x48
SEL_CGATE2  equ 0x50
SEL_LIM4    equ 0x58

BEYOND      equ 0x3000
STACK0_TOP  equ 0x6000
STACK3_TOP  equ 0x7000

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
    mov es, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax

; %1 case, %2 the faulting instruction's label
%macro CHECK_GP 2
    cmp dword [gp_count], %1
    mov eax, (%1 << 8) | 1
    jne fail
    test word [gp_err], 0xFFFE          ; 0, EXT not examined here
    mov eax, (%1 << 8) | 2
    jnz fail
    cmp dword [gp_eip], %2
    mov eax, (%1 << 8) | 3
    jne fail
    test byte [gdt + SEL_LIM + 5], 1
    mov eax, (%1 << 8) | 4
    jnz fail
%endmacro

    mov dword [resume], .r1
    mov [saved_esp], esp
.i1:
    int 0x40
    mov eax, 0x0100
    jmp fail
.r1:
    CHECK_GP 1, .i1

    mov dword [resume], .r2
    mov [saved_esp], esp
.i2:
    int 0x41
    mov eax, 0x0200
    jmp fail
.r2:
    CHECK_GP 2, .i2

    mov dword [resume], .r3
    mov [saved_esp], esp
.i3:
    ud2
    mov eax, 0x0300
    jmp fail
.r3:
    CHECK_GP 3, .i3

    ; case 4: to ring 3, INT 43h there
    mov dword [resume], .r4
    mov [saved_esp], esp
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword SEL_CODE3 | 3
    push dword ring3
    retf
.r4:
    CHECK_GP 4, ring3.i4
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax

    mov dword [resume], .r5
    mov [saved_esp], esp
.i5:
    call SEL_CGATE:0
    mov eax, 0x0500
    jmp fail
.r5:
    CHECK_GP 5, .i5

    mov dword [resume], .r6
    mov [saved_esp], esp
.i6:
    jmp SEL_CGATE:0
    mov eax, 0x0600
    jmp fail
.r6:
    CHECK_GP 6, .i6

    ; case 7: in-limit control
    test byte [gdt + SEL_LIM2 + 5], 1
    mov eax, 0x0701
    jnz fail
    xor ecx, ecx
    int 0x42
    cmp ecx, 0x4242
    mov eax, 0x0702
    jne fail
    test byte [gdt + SEL_LIM2 + 5], 1
    mov eax, 0x0703
    jz fail
    cmp dword [gp_count], 6
    mov eax, 0x0704
    jne fail
    test byte [gdt + SEL_LIM3 + 5], 1   ; INT 44h from ring 3
    mov eax, 0x0705
    jz fail
    test byte [gdt + SEL_LIM4 + 5], 1
    mov eax, 0x0706
    jnz fail
    xor ecx, ecx
    call SEL_CGATE2:0
    cmp ecx, 0x5050
    mov eax, 0x0707
    jne fail
    test byte [gdt + SEL_LIM4 + 5], 1
    mov eax, 0x0708
    jz fail

    mov al, STATUS_PASS
    out STATUS_PORT, al
    hlt

ring3:
    xor ecx, ecx
    int 0x44                    ; inner level, in limit
    cmp ecx, 0x4444
    jne $
.i4:
    int 0x43
    jmp $

fail:
    out DATA_PORT, eax
    mov al, STATUS_FAIL
    out STATUS_PORT, al
    hlt

; #GP (interrupt gate, ring 0): record, resume in ring 0 at [resume]
isr_gp:
    mov ax, SEL_DATA0
    mov ds, ax
    pop dword [gp_err]
    pop dword [gp_eip]
    inc dword [gp_count]
    mov esp, [saved_esp]
    jmp [resume]

isr_42:
    mov ecx, 0x4242
    iretd

isr_44:
    mov ecx, 0x4444
    iretd

cg_target:
    mov ecx, 0x5050
    retf

isr_other:
    mov eax, 0xEEEE
    jmp fail

align 4
resume:     dd 0
saved_esp:  dd 0
gp_err:     dd 0
gp_eip:     dd 0
gp_count:   dd 0

;==================================================================
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0 flat (base 10000h)
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x00409A0100001FFF       ; 0x18 code0, limit 1FFFh, A clear
    dq 0x00CFFB010000FFFF       ; 0x20 code3
    dq 0x00409A0100001FFF       ; 0x28 code0, limit 1FFFh, A clear
    dq 0x00CFF3010000FFFF       ; 0x30 data3
    dw 0x0067                   ; 0x38 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dw BEYOND                   ; 0x40 386 call gate DPL 0 -> 18h:3000h
    dw SEL_LIM
    db 0
    db 0x8C
    dw 0
    dq 0x00409A0100001FFF       ; 0x48 code0, limit 1FFFh, A clear
    dw cg_target                ; 0x50 386 call gate DPL 0 -> 58h:cg_target
    dw SEL_LIM4
    db 0
    db 0x8C
    dw 0
    dq 0x00409A0100001FFF       ; 0x58 code0, limit 1FFFh, A clear
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro GATE 3                   ; offset (< 10000h), selector, type/DPL byte
    dw %1
    dw %2
    db 0
    db %3
    dw 0
%endmacro

align 8
idt:
%rep 6
    GATE isr_other, SEL_CODE0, 10001110b
%endrep
    GATE BEYOND, SEL_LIM, 10001111b         ; 6: #UD, trap gate
%rep 6
    GATE isr_other, SEL_CODE0, 10001110b
%endrep
    GATE isr_gp, SEL_CODE0, 10001110b       ; 0x0D
%rep 0x40 - 14
    GATE isr_other, SEL_CODE0, 10001110b
%endrep
    GATE BEYOND, SEL_LIM, 10001110b         ; 0x40
    GATE BEYOND, SEL_LIM, 10000110b         ; 0x41: 16-bit interrupt gate
    GATE isr_42, SEL_LIM2, 10001110b        ; 0x42
    GATE BEYOND, SEL_LIM, 11101110b         ; 0x43: DPL 3
    GATE isr_44, SEL_LIM3, 11101110b        ; 0x44: DPL 3
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
