; io_bitmap_cpl3.asm - I/O permission bitmap at CPL 3, IOPL 0
;
; i486 PRM 8.3.2: with CPL > IOPL, an I/O instruction is allowed only if
; every bitmap bit for the ports it touches is 0; the bits are read from
; the TSS at the I/O map base + port/8 (two bytes), and a bitmap byte past
; the TSS limit counts as set.
;
; The bitmap covers ports 0x00-0x8F (18 bytes), all clear except port
; 0x81 and port 0x88; the TSS limit ends right after it, plus the
; terminating 0xFF byte.
;
; Each case runs an OUT at CPL 3; the #GP handler counts faults and
; records which case faulted. Expected faulting cases:
;   0 out 0x80 (byte)            no
;   1 out 0x81 (byte)            yes
;   2 out 0x80 (word: 80,81)     yes
;   3 out 0x82 (word: 82,83)     no
;   4 out 0x84 (dword: 84..87)   no
;   5 out 0x86 (dword: 86..89)   yes (0x88)
;   6 out 0x8C (dword: 8C..8F)   no
;   7 in  0x8E (word: 8E,8F)     no
;   8 out 0x100 (past the limit) yes
;   9 in  0x8F (byte)            no
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code
; (faulted mask, then expected).

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
EXPECT      equ (1<<1)|(1<<2)|(1<<5)|(1<<8)

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
    push dword 0x00000002       ; IOPL 0
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

%macro CASE 2                   ; %1 index, %2 instruction
    mov dword [cur], %1
    %2
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    xor eax, eax
    CASE 0, {out 0x80, al}
    CASE 1, {out 0x81, al}
    CASE 2, {out 0x80, ax}
    CASE 3, {out 0x82, ax}
    CASE 4, {out 0x84, eax}
    CASE 5, {out 0x86, eax}
    CASE 6, {out 0x8C, eax}
    CASE 7, {in ax, 0x8E}
    mov dx, 0x100
    CASE 8, {out dx, al}
    CASE 9, {in al, 0x8F}
    mov dword [cur], 0xFF
    int3                        ; to ring 0 through a DPL 3 gate: report

;------------------------------------------------------------------
isr_gp:
    ; [esp]=err, +4 EIP, +8 CS
    push eax
    push ecx
    push ds
    mov ax, SEL_DATA0
    mov ds, ax
    mov ecx, [cur]
    cmp ecx, 16
    jae .bad
    bts [faulted], ecx
    ; skip the faulting I/O instruction: 2 bytes (imm8 form), 1 (DX form)
    mov eax, [esp+16]           ; EIP
    cmp byte [eax], 0xEE
    je .one
    cmp byte [eax], 0x66        ; operand-size prefix + imm8 form
    jne .two
    inc dword [esp+16]
.two:
    add dword [esp+16], 2
    jmp .ret
.one:
    inc dword [esp+16]
.ret:
    pop ds
    pop ecx
    pop eax
    add esp, 4
    iretd
.bad:
    mov eax, 0xBAD0000
    or eax, ecx
    mov dx, DATA_PORT
    out dx, eax
    jmp report_fail

isr_report:
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, [faulted]
    cmp eax, EXPECT
    jne .fail
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
.fail:
    mov dx, DATA_PORT
    out dx, eax
    mov eax, EXPECT
    out dx, eax
report_fail:
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

;==================================================================
align 4
cur:
    dd 0
faulted:
    dd 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x0000000000000000       ; 0x18 unused
    dq 0x00CFF3010000FFFF       ; 0x20 data3
    dw tss_end - tss386 - 1     ; 0x28 TSS
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

align 8
idt:
    times 3 dq 0
    dw isr_report               ; 3: INT3, DPL 3 interrupt gate
    dw SEL_CODE0
    db 0
    db 11101110b
    dw 0
    times 0x0D - 4 dq 0
    dw isr_gp                   ; 0x0D
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
    dd STACK0_TOP
    dd SEL_DATA0
    times 22 dd 0
    dw 0
    dw iomap - tss386           ; +0x66: I/O map base
iomap:
    times 16 db 0               ; ports 0x00-0x7F
    db 0x02                     ; ports 0x80-0x87: 0x81
    db 0x01                     ; ports 0x88-0x8F: 0x88
    db 0xFF                     ; terminator
tss_end:
