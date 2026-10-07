; conforming_xfer - far transfers into conforming code keep the CPL
;
; A far JMP/CALL to a conforming segment does not change the CPL: the new CS
; carries RPL = CPL whatever the selector's RPL or the descriptor's DPL is.
;   1) From real mode's PE entry (CPL0) by far JMP with selector RPL 3 to a
;      conforming DPL0 segment: CS reads SEL_CONF|0 and LIDT still executes.
;   2) Far CALL from that conforming CPL0 code to a conforming DPL0 segment
;      through an RPL 3 selector: CPL0, pushed CS = SEL_CONF|0.
;   3) From CPL3 by far CALL to conforming DPL0 code (selector RPL 0): the
;      CPL stays 3 (CS reads SEL_CONF|3) and LIDT raises #GP(0).
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CONF    equ 0x18        ; conforming DPL0 32-bit code
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_CODE3   equ 0x30

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword (SEL_CONF | 3):conf_entry   ; RPL 3 selector, still CPL0

BITS 32
conf_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x3000
    mov ax, cs
    cmp ax, SEL_CONF
    jne fail_1
    lidt [idt_desc]                 ; CPL0: legal
    mov ax, SEL_TSS
    ltr ax
    call dword (SEL_CONF | 3):conf_sub
    cmp ebx, SEL_CONF
    jne fail_2
    ; Drop to CPL3 in ordinary code, then call conforming DPL0 code.
    push dword SEL_DATA3 | 3
    push dword 0x4000
    push dword 0x3002
    push dword SEL_CODE3 | 3
    push dword ring3
    iretd

conf_sub:
    mov ebx, [esp + 4]              ; pushed CS
    retf

ring3:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    call dword SEL_CONF:conf3       ; selector RPL 0, CPL stays 3
    jmp fail_5
conf3:
    mov ax, cs
    cmp ax, SEL_CONF | 3
    jne fail_3
lidt_site:
    lidt [idt_desc]                 ; CPL3: #GP(0)
    jmp fail_4

isr_gp:
    cmp dword [esp], 0
    jne fail_6
    cmp dword [esp + 4], lidt_site
    jne fail_6
    cmp word [esp + 8], SEL_CONF | 3
    jne fail_6
    mov ax, SEL_DATA0
    mov ds, ax
    mov al, 1
    out STATUS_PORT, al
    hlt

%assign c 1
%rep 6
fail_ %+ c:
    mov eax, c
    jmp fail
%assign c c+1
%endrep
fail:
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08 code DPL0
    dq 0x00CF93010000FFFF       ; 10 data DPL0
    dq 0x00CF9F010000FFFF       ; 18 conforming code DPL0
    dq 0x00CFF3010000FFFF       ; 20 data DPL3
    dw 0x0067                   ; 28 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CFFB010000FFFF       ; 30 code DPL3
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times 0x0D dq 0
    dw isr_gp
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss386:
    dd 0
    dd 0x3000
    dd SEL_DATA0
    times 23 dd 0
