; outer_ret_segs.asm - segment registers after a return to an outer level
;
; i486 PRM (RET, IRET): on a return to a less privileged level, ES, FS, GS
; and DS are each checked; one that holds a data segment or a
; non-conforming code segment whose DPL is below the new CPL is loaded
; with the null selector. Conforming code, and segments with DPL >= new
; CPL, are kept.
;
; Ring 0 loads DS = data DPL 0, ES = data DPL 3, FS = conforming readable
; code DPL 0, GS = non-conforming readable code DPL 0, then RETF to ring 3.
; Ring 3 checks DS = 0, ES kept, FS kept, GS = 0; then it calls back to
; ring 0 through a gate, reloads the same set and returns with IRETD, and
; checks again. Last, an IDT gate whose target selector has RPL 3 (the
; RPL is ignored) must run its handler at CPL 0.
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
SEL_CONF0   equ 0x18    ; conforming readable code, DPL 0
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_CODE3   equ 0x30
SEL_RCODE0  equ 0x38    ; non-conforming readable code, DPL 0
SEL_GATE    equ 0x40    ; 386 call gate, DPL 3 -> reload_and_iret

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
    call load_set
    ; RETF to ring 3: SS3:ESP3, CS3:EIP3
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword SEL_CODE3 | 3
    push dword ring3_after_retf
    retf

load_set:
    mov ax, SEL_DATA3 | 3
    mov es, ax
    mov ax, SEL_CONF0
    mov fs, ax
    mov ax, SEL_RCODE0
    mov gs, ax
    mov ax, SEL_DATA0
    mov ds, ax
    ret

; ring 3 check: DS=0, ES=DATA3|3, FS=CONF0, GS=0. Uses only registers.
%macro CHECK 1
    mov ax, ds
    cmp ax, 0
    mov ebx, (%1 << 8) | 1
    jne r3_fail
    mov ax, es
    cmp ax, SEL_DATA3 | 3
    mov ebx, (%1 << 8) | 2
    jne r3_fail
    mov ax, fs
    cmp ax, SEL_CONF0
    mov ebx, (%1 << 8) | 3
    jne r3_fail
    mov ax, gs
    cmp ax, 0
    mov ebx, (%1 << 8) | 4
    jne r3_fail
%endmacro

ring3_after_retf:
    CHECK 1
    call SEL_GATE|3:0
ring3_after_iret:
    CHECK 2
    int 0x40                    ; IDT gate, target selector RPL 3
    cmp ecx, 0x5A5A
    mov ebx, 0x0305
    jne r3_fail
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    mov dx, STATUS_PORT         ; IOPL 3
    mov al, STATUS_PASS
    out dx, al
    jmp $

r3_fail:
    mov eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp $

; Ring 0, through the call gate: reload the set and IRETD to ring 3
reload_and_iret:
    call load_set
    add esp, 16                 ; drop the gate's frame
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword 0x00003002       ; IOPL 3
    push dword SEL_CODE3 | 3
    push dword ring3_after_iret
    iretd

; INT 0x40 handler: must run at CPL 0 with CS = SEL_CODE0
isr_40:
    mov ax, cs
    cmp ax, SEL_CODE0
    jne .bad
    mov ecx, 0x5A5A
    iretd
.bad:
    xor ecx, ecx
    iretd

isr_fault:
    mov eax, [esp+4]            ; EIP (error code at [esp])
    shl eax, 8
    mov al, 0xEE
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

;==================================================================
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
    dq 0x00CF9B010000FFFF       ; 0x38 readable code, DPL 0
    dw reload_and_iret          ; 0x40 386 call gate, DPL 3
    dw SEL_CODE0
    db 0
    db 0xEC
    dw 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro FGATE 0
    dw isr_fault
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
%rep 0x40
    FGATE
%endrep
    dw isr_40                   ; 0x40: DPL 3 interrupt gate, target RPL 3
    dw SEL_CODE0 | 3
    db 0
    db 11101110b
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
    dw 104
