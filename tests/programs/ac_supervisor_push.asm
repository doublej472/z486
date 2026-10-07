; ac_supervisor_push - implicit privilege-level-0 stack accesses made on behalf
; of CPL3 code never raise #AC
;
; 486 PRM 9.9.16: "Memory references which default to privilege level 0, such
; as segment descriptor loads, do not generate alignment-check faults, even
; when caused by a memory reference made in user mode."  With AM=1, AC=1 and
; CPL3, an INT n through a DPL3 gate and a CALL through a call gate switch to
; a misaligned ring-0 stack (ESP0 = 2 mod 4); the frame pushes are made at
; privilege level 0 and must not fault.  (Derived from align_check.)
;
; original header:
;
; #AC requires CR0.AM=1, EFLAGS.AC=1 and CPL3.  A misaligned word or dword
; data access faults with error code 0 and restarts at the instruction; bytes
; and aligned accesses never fault, and a segment-limit fault on the same
; access has priority.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_SMALL3  equ 0x30                 ; ring-3 data, limit 0xFFF
SEL_GATE    equ 0x38
R3_STACK    equ 0x00003000
R0_STACK    equ 0x00014000
BUF         equ 0x00002000

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  eax, 0x00040001              ; PE, AM
    mov cr0, eax
    jmp SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, R0_STACK
    mov ax, SEL_TSS
    ltr ax
    ; CPL0 with AC set never checks alignment.
    push dword 0x40002
    popfd
    mov eax, [BUF + 1]
    push dword SEL_DATA3 | 3
    push dword R3_STACK
    push dword 0x40202               ; AC, IF
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

; ACX: expect #AC on the instruction; EXPECT_NONE: expect no fault.
%macro ACX 1+
    mov edi, %%after
    mov esi, %%site
    inc ebx
%%site:
    %1
%%after:
    cmp ebp, ebx
    jne bad3
%endmacro
%macro NOAC 1+
    %1
    cmp ebp, ebx
    jne bad3
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    mov es, ax
    xor ebx, ebx
    xor ebp, ebp
    xor edx, edx
    int 0x23                         ; ring-0 frame on a misaligned ESP0
    cmp edx, 1
    jne bad3
    cmp ebp, 0
    jne bad3
    call dword 0x3b:0                ; call gate (SEL_GATE|3), same misaligned ESP0
    cmp edx, 2
    jne bad3
    cmp ebp, 0
    jne bad3
    int 0x21
bad3:
    int 0x22

ac_handler:
    cmp dword [esp], 0               ; error code 0
    jne bad0
    cmp [esp+4], esi                 ; restarts at the faulting instruction
    jne bad1
    test dword [esp+12], 0x40000     ; AC still set in the saved EFLAGS
    jz bad1
    inc ebp
    mov [esp+4], edi
    add esp, 4
    iretd
gp_handler:
    cmp esi, -1                      ; no #GP expected here
    jne bad2
    inc ebp
    mov [esp+4], edi
    add esp, 4
    iretd
bad0:
    mov eax, 0x1100
    jmp report_fail
bad1:
    mov eax, 0x2200
    jmp report_fail
bad2:
    mov eax, 0x3300
report_fail:
    add eax, ebx
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt
int23_handler:
    inc edx
    iretd
gate_target:
    inc edx
    retf
pass_handler:
    mov al, 1
    out STATUS_PORT, al
    hlt
fail_handler:
    mov eax, ebx
    jmp report_fail

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
    dq 0x00cffb010000ffff
    dq 0x00cff3000000ffff
tss_desc:
    dw 0x0067
    dw tss
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x0040f3000000_0fff           ; SEL_SMALL3: byte granular, limit 0xFFF
    dw gate_target, SEL_CODE0        ; 38: call gate, DPL3, 0 params
    db 0, 0xec
    dw 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

%macro GATE 2
    dw %1
    dw SEL_CODE0
    db 0, %2
    dw 0
%endmacro
align 8
idt:
    times 13 dq 0
    GATE gp_handler, 0x8e
    times 3 dq 0
    GATE ac_handler, 0x8e
    times (0x21 - 18) dq 0
    GATE pass_handler, 0xee
    GATE fail_handler, 0xee
    GATE int23_handler, 0xee
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    dd 0, R0_STACK - 2, SEL_DATA0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 104
