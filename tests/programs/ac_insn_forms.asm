; ac_insn_forms - #AC for multi-access and string instruction forms
;
; 486 PRM Table 9-6: word 2, dword 4, selector 2, 48-bit segmented pointer 4,
; 32-bit segmented pointer 2.  (Derived from align_check.)
;
; original header (align_check):
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
R3_STACK    equ 0x00003000
R0_STACK    equ 0x00014000
BUF         equ 0x00002000
SITE_V      equ 0x00002100
AFTER_V     equ 0x00002104

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
    mov dword [AFTER_V], %%after
    mov dword [SITE_V], %%site
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
    mov esi, BUF + 1
    mov edi, BUF + 0x40
    mov ecx, 1
    push esi
    mov edx, esi
    ACX movsw                        ; misaligned source
    mov esi, BUF + 2
    mov edi, BUF + 0x41
    ACX movsw                        ; misaligned destination
    mov edi, BUF + 0x42
    ACX stosd
    mov esi, BUF + 0x43
    ACX lodsw
    mov esi, BUF + 4
    mov edi, BUF + 0x46
    ACX cmpsd
    ACX bound eax, [BUF + 0x21]
    ACX cmpxchg [BUF + 0x22], ecx
    ACX xadd [BUF + 0x23], ecx
    ACX les eax, [BUF + 0x32]        ; 48-bit pointer at 2 mod 4
    mov dword [BUF + 0x50], 0
    mov word [BUF + 0x54], SEL_DATA3 | 3
    ACX o16 les ax, [BUF + 0x51]     ; 32-bit pointer at an odd address
    mov word [BUF + 0x56], 0
    mov word [BUF + 0x58], SEL_DATA3 | 3
    NOAC o16 les ax, [BUF + 0x56]    ; 32-bit pointer at 2 mod 4: aligned words
    mov ax, SEL_DATA3 | 3
    mov es, ax
    ACX mov es, [BUF + 0x57]         ; selector at an odd address
    ACX sgdt [BUF + 0x60]            ; pseudo-descriptor at 0 mod 4: dword at +2
    NOAC sgdt [BUF + 0x62]           ; 2 mod 4: aligned word + aligned dword
    pop esi
    mov esp, R3_STACK - 2
    ACX pushfd
    ACX call R3_STACK                ; (faults on the push)
    mov esp, R3_STACK
    ; (ENTER is not covered here: it rewrites EBP, the fault counter)
    int 0x21
bad3:
    int 0x22

ac_handler:
    cmp dword [esp], 0               ; error code 0
    jne bad0
    push eax
    mov eax, [SITE_V]
    cmp [esp+8], eax                 ; restarts at the faulting instruction
    pop eax
    jne bad1
    test dword [esp+12], 0x40000     ; AC still set in the saved EFLAGS
    jz bad1
    inc ebp
    push eax
    mov eax, [AFTER_V]
    mov [esp+8], eax
    pop eax
    add esp, 4
    iretd
gp_handler:
    jmp bad2
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
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    dd 0, R0_STACK, SEL_DATA0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 104
