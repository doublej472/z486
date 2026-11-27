; outer_ret_null_use.asm - a segment register nulled by a return to an outer
; level faults on use
;
; i486 PRM (1992), RET, "return to outer privilege level": "For each of ES,
; FS, GS, and DS: If the current register setting is not valid for the
; outer level, set the register to null (selector <- AR <- 0)" (IRET the
; same). Interrupt 13: #GP(0) for "Using a null selector to address memory"
; (9.9.13).
;
; Ring 0 loads DS/ES/FS/GS with a DPL 0 data segment and returns to ring 3,
; by RETF (case 1-5) and by IRETD (case 6). Ring 3 reads through each nulled
; register and writes through DS: each must raise #GP(0) at the instruction
; and leave the destination register unchanged. Case 7: the ring-0 handler of
; an INT n from ring 3 reads through the still-null DS: #GP(0) in ring 0.
; Control: a same-level RETF in ring 0 keeps DS usable (case 8).
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_CODE3   equ 0x30

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
    mov dword [gp_count], 0

    ; case 8 (control): a same-level RETF keeps DS
    push dword SEL_CODE0
    push dword .same
    retf
.same:
    mov eax, [probe]
    cmp eax, 0x13579BDF
    mov ebx, 0x0801
    jne fail0

    call load_set
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword SEL_CODE3 | 3
    push dword ring3_retf
    retf

load_set:
    mov ax, SEL_DATA0
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ds, ax
    ret

; one ring-3 probe: %1 case, %2 the instruction (must fault, ECX kept)
%macro R3CASE 2
    mov dword [ss:resume], %%next
    mov dword [ss:fault_eip], 0
    mov ecx, 0xC0DEC0DE
%%insn:
    %2
    mov ebx, (%1 << 8) | 1          ; not faulted
    jmp r3_fail
%%next:
    cmp ecx, 0xC0DEC0DE
    mov ebx, (%1 << 8) | 2
    jne r3_fail
    cmp dword [ss:fault_eip], %%insn
    mov ebx, (%1 << 8) | 3
    jne r3_fail
    cmp dword [ss:fault_err], 0
    mov ebx, (%1 << 8) | 4
    jne r3_fail
%endmacro

ring3_retf:
    R3CASE 1, {mov ecx, [ds:probe]}
    R3CASE 2, {mov ecx, [es:probe]}
    R3CASE 3, {mov ecx, [fs:probe]}
    R3CASE 4, {mov ecx, [gs:probe]}
    R3CASE 5, {mov dword [ds:probe], ecx}
    int 0x30                        ; reload the set and IRETD back here
ring3_iret:
    R3CASE 6, {mov ecx, [ds:probe]}
    int 0x31                        ; case 7, then the verdict
    jmp $

r3_fail:
    mov [ss:r3_code], ebx
    int 0x32
    jmp $

; INT 0x30 (DPL 3): load the set and IRETD to ring 3
isr_30:
    call load_set
    add esp, 20
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword 0x00000002
    push dword SEL_CODE3 | 3
    push dword ring3_iret
    iretd

; INT 0x31 (DPL 3): case 7, the handler reads through the null DS
isr_31:
    mov dword [ss:resume], .next
    mov dword [ss:fault_eip], 0
    mov ecx, 0xC0DEC0DE
.insn:
    mov ecx, [ds:probe]
    mov ebx, 0x0701
    jmp fail0
.next:
    cmp ecx, 0xC0DEC0DE
    mov ebx, 0x0702
    jne fail0
    cmp dword [ss:fault_eip], .insn
    mov ebx, 0x0703
    jne fail0
    cmp dword [ss:fault_err], 0
    mov ebx, 0x0704
    jne fail0
    cmp dword [ss:gp_count], 7
    mov ebx, 0x0705
    jne fail0
    mov al, STATUS_PASS
    out STATUS_PORT, al
    hlt

; INT 0x32 (DPL 3): a ring-3 failure, code in r3_code
isr_32:
    mov ebx, [ss:r3_code]
fail0:
    mov eax, ebx
    out DATA_PORT, eax
    mov al, STATUS_FAIL
    out STATUS_PORT, al
    hlt

; #GP: record error code and EIP, resume at [resume]. Only SS is used
isr_gp:
    pop dword [ss:fault_err]
    mov eax, [esp]
    mov [ss:fault_eip], eax
    inc dword [ss:gp_count]
    mov eax, [ss:resume]
    mov [esp], eax
    iretd

isr_fault:
    mov eax, [esp]
    shl eax, 8
    mov al, 0xEE
    out DATA_PORT, eax
    mov al, STATUS_FAIL
    out STATUS_PORT, al
    hlt

align 4
probe:      dd 0x13579BDF
resume:     dd 0
fault_eip:  dd 0
fault_err:  dd 0
gp_count:   dd 0
r3_code:    dd 0

;==================================================================
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x0000000000000000       ; 0x18
    dq 0x00CFF3010000FFFF       ; 0x20 data3
    dw 0x0067                   ; 0x28 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CFFB010000FFFF       ; 0x30 code3
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro GATE 2                   ; handler, type/DPL byte
    dw %1
    dw SEL_CODE0
    db 0
    db %2
    dw 0
%endmacro

align 8
idt:
%rep 13
    GATE isr_fault, 10001110b
%endrep
    GATE isr_gp, 10001110b      ; 0x0D
%rep 0x30 - 14
    GATE isr_fault, 10001110b
%endrep
    GATE isr_30, 11101110b      ; 0x30
    GATE isr_31, 11101110b      ; 0x31
    GATE isr_32, 11101110b      ; 0x32
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
