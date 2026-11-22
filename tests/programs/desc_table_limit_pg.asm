; desc_table_limit_pg - the descriptor-table limit #GP comes before any read
; of the descriptor
;
; The selector's index is checked against the GDT/LDT limit before the
; descriptor is read (i486 PRM (240486) MOV/JMP/LLDT/LTR pseudo-code: "IF
; segment selector index is not within its descriptor table limits THEN
; #GP(selector)", the descriptor is read only after that test).  Here the GDT
; and an LDT each end exactly at a page boundary and the next page is not
; present, so a CPU that touches the 8 bytes beyond the table raises #PF
; instead of the #GP(selector) owed.  z486 checked the limit in the protection
; test but still issued the descriptor's first read in the cycle the fault
; redirect was taken.  (Companion of desc_table_limit.)
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number
; (EBX), 0xE0 + case for a #PF, 0x8000 + n for another exception n.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

GDT         equ 0x9FD0          ; 30h bytes, ends at the not-present page A000h
LDT         equ 0xBFF0          ; 10h bytes, ends at the not-present page C000h
IDT         equ 0x8800
VARS        equ 0x8F00
FAULT_EIP   equ VARS + 0
SAVED_ESP   equ VARS + 4
GDTR        equ VARS + 8
IDTR        equ VARS + 16

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_DATA3   equ 0x18
SEL_LDT     equ 0x20
SEL_X       equ 0x30            ; first selector past the GDT limit (2Fh)
LSEL_IN     equ 0x0F            ; LDT entry 1, RPL 3 (inside)
LSEL_X      equ 0x17            ; LDT entry 2, RPL 3 (past the LDT limit 0Fh)

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
    mov dword [GDT + 0x18], 0x0000FFFF  ; 18: flat data DPL 3
    mov dword [GDT + 0x1C], 0x00CFF300
    mov dword [GDT + 0x20], (LDT << 16) | 0x000F   ; 20: LDT, limit 0Fh
    mov dword [GDT + 0x24], 0x00008200
    mov dword [GDT + 0x28], 0x0000FFFF  ; 28: flat data DPL 0
    mov dword [GDT + 0x2C], 0x00CF9300
    mov dword [LDT + 0x00], 0
    mov dword [LDT + 0x04], 0
    mov dword [LDT + 0x08], 0x0000FFFF  ; 0C: flat data DPL 3
    mov dword [LDT + 0x0C], 0x00CFF300
    mov word [GDTR], 0x2F
    mov dword [GDTR + 2], GDT
    lgdt [GDTR]
%assign v 0
%rep 14
    GATE v, unexpected
%assign v v+1
%endrep
    GATE 13, gp_handler
    GATE 14, pf_handler
    mov word [IDTR], 15*8 - 1
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

    ; in-limit boundary loads (the last GDT entry, the last LDT entry)
    inc ebx
    mov ax, 0x28
    mov gs, ax
    mov ax, SEL_LDT
    lldt ax
    mov ax, LSEL_IN
    mov fs, ax

    mov ax, SEL_X                       ; (the #GP handler uses EAX)
    EXPECT_GP SEL_X, mov gs, ax
    mov ax, SEL_X
    EXPECT_GP SEL_X, mov ss, ax
    EXPECT_GP SEL_X, jmp SEL_X:0
    EXPECT_GP SEL_X, call SEL_X:0
    mov ax, SEL_X
    EXPECT_GP SEL_X, lldt ax
    mov ax, SEL_X
    EXPECT_GP SEL_X, ltr ax
    mov ax, LSEL_X
    EXPECT_GP LSEL_X & 0xFFFC, mov es, ax
    EXPECT_GP LSEL_X & 0xFFFC, jmp LSEL_X:0

    mov ax, gs
    cmp ax, 0x28
    jne fail
    mov ax, es
    cmp ax, SEL_DATA0
    jne fail

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
