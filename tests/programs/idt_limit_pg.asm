; idt_limit_pg - the IDT limit #GP comes before any read of the gate, and a
; page fault whose gate lies beyond the limit is a double fault
;
; i486 PRM (Intel 240486), INT/INTO pseudo-code (p. 26-166, "applies not only
; to the above instructions but also to external interrupts and exceptions"):
; "Interrupt vector must be within IDT table limits, else #GP(vector number *
; 8+2+EXT)"; the gate is examined only after that test.  Here the IDT ends
; exactly at a page boundary and the next page is not present, so a CPU that
; reads a gate beyond the limit raises #PF instead of the #GP owed.
; 9.9.8 Interrupt 8 - Double Fault: "if a page fault is followed by a
; contributory exception or another page fault, a double-fault abort is
; generated"; #GP is contributory (Table 9-4), so a #PF whose gate lies beyond
; the limit is delivered as #DF with error code 0.  (Companion of idt_limit.)
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number
; (EBX), 0xE0 + case for a #PF, 0x8000 for another exception.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

IDT         equ 0x9F80          ; 80h bytes (vectors 00h-0Fh), ends at the
                                ; not-present page A000h
GDT         equ 0x8800
VARS        equ 0x8F00
FAULT_EIP   equ VARS + 0
SAVED_ESP   equ VARS + 4
GDTR        equ VARS + 8
IDTR        equ VARS + 16
NOT_PRESENT equ 0xC000          ; a not-present page for the #PF case

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10

%macro GATE 2                   ; vector, handler
    mov eax, %2
    mov word [IDT + %1*8 + 0], ax
    mov word [IDT + %1*8 + 2], SEL_CODE0
    mov word [IDT + %1*8 + 4], 0x8E00
    shr eax, 16
    mov word [IDT + %1*8 + 6], ax
%endmacro

start:
    mov esp, 0x8000
    xor ebx, ebx
    xor ecx, ecx
    mov dword [GDT + 0x00], 0
    mov dword [GDT + 0x04], 0
    mov dword [GDT + 0x08], 0x0000FFFF  ; 08: code DPL 0, base 10000h
    mov dword [GDT + 0x0C], 0x00CF9B01
    mov dword [GDT + 0x10], 0x0000FFFF  ; 10: flat data DPL 0
    mov dword [GDT + 0x14], 0x00CF9300
    mov word [GDTR], 0x17
    mov dword [GDTR + 2], GDT
    lgdt [GDTR]
%assign v 0
%rep 16
    GATE v, unexpected
%assign v v+1
%endrep
    GATE 8, df_handler
    GATE 13, gp_handler
    GATE 14, pf_handler
    mov word [IDTR], 0x7F
    mov dword [IDTR + 2], IDT
    lidt [IDTR]
    jmp SEL_CODE0:reload
reload:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

%macro EXPECT_GP 2+
    inc ebx
    mov ebp, %1
    mov edi, %%resume
    mov dword [FAULT_EIP], %%insn + 0x10000
    mov [SAVED_ESP], esp
%%insn:
    %2
    jmp fail
%%resume:
    cmp ecx, ebx
    jne fail
%endmacro

    ; the gate just past the limit is on the not-present page
    EXPECT_GP 0x10*8+2, int 0x10
    EXPECT_GP 0x40*8+2, int 0x40
    EXPECT_GP 0xFF*8+2, int 0xFF

    ; a page fault whose gate (0Eh) is beyond the limit: #GP after #PF is #DF
    mov word [IDTR], 0x6F               ; vectors 00h-0Dh
    lidt [IDTR]
    inc ebx
    mov edi, .df_resume
    mov [SAVED_ESP], esp
    mov eax, [NOT_PRESENT]
    jmp fail
.df_resume:
    cmp ecx, ebx
    jne fail
    mov word [IDTR], 0x7F
    lidt [IDTR]

    mov al, 0x01
    out STATUS_PORT, al
    hlt

pf_handler:
    lea eax, [ebx + 0xE0]
    jmp report
unexpected:
    mov eax, 0x8000
    jmp report
fail:
    mov eax, ebx
report:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

gp_handler:
    cmp [esp], bp
    jne fail
    mov eax, [esp+4]
    add eax, 0x10000                    ; frame EIP is CS-relative
    cmp eax, [FAULT_EIP]
    jne fail
    lea eax, [esp+16]
    cmp eax, [SAVED_ESP]
    jne fail
    mov ecx, ebx
    mov esp, [SAVED_ESP]
    jmp edi

; #DF: error code 0 (9.9.8), then resume.
df_handler:
    cmp word [esp], 0
    jne fail
    mov ecx, ebx
    mov esp, [SAVED_ESP]
    jmp edi
