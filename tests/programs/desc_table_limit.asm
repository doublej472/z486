; desc_table_limit.asm - a selector beyond the GDT/LDT limit raises #GP(selector)
;
; Every segment-register and system-register load checks the selector's index
; against the limit of the table it names (TI=0 GDT, TI=1 LDT) before it reads
; the descriptor.  i486 PRM (Intel 240486), instruction set reference:
;   MOV, POP, LDS/LES/LFS/LGS/LSS: "Selector index must be within its
;     descriptor table limits else #GP(selector)" (the SS case after the null
;     test, DS/ES/FS/GS for a non-null selector);
;   JMP/CALL far: the destination selector "index is within its descriptor
;     table limits else #GP(selector)", the same for a call gate's code
;     selector;
;   RET/IRET (same level): "Return selector index must be within its
;     descriptor table limits ELSE #GP(return selector)";
;   INT n: the gate's code selector "must be within its descriptor table
;     limits ELSE #GP(selector+EXT)" (EXT = 0 for INT n);
;   LLDT, LTR: #GP(selector) for a selector that does not index into the GDT.
; LLDT also: "If the source operand is 0, the LDTR is marked invalid and all
; descriptor references (except by LAR, VERR, VERW or LSL) cause a #GP fault":
; a TI=1 selector with a null LDTR (after reset, or after LLDT 0) has no table.
; The error code is the selector with its RPL bits cleared.
;
; The test places a valid descriptor of the matching kind in the 8 bytes just
; past the GDT limit (and past an LDT limit), so a CPU that reads it without the
; limit check loads it.  z486 did: MOV GS,58h loaded the descriptor behind the
; table and a far JMP ran in the out-of-table code segment.  For the null-LDTR
; cases a valid descriptor sits where the stale LDT cache points (linear 8 after
; reset; the old LDT after LLDT 0).  Each case checks
; the #GP error code (low word; the upper half is a separate issue), the
; faulting EIP, that the frame's ESP is the instruction's starting ESP (CALL
; pushed nothing, POP/RETF/IRET popped nothing), and that the target register
; kept its old value.  In-limit sanity loads at each boundary still succeed.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number
; (EBX) or 0x8000+n for an unexpected exception n.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_DATA3   equ 0x18
SEL_LDT     equ 0x20
SEL_CGATE   equ 0x28        ; call gate, DPL 0, target SEL_X_CODE (beyond)
; past the GDT limit (2Fh):
SEL_X_DATA3 equ 0x30        ; data DPL 3
SEL_X_CODE  equ 0x38        ; 32-bit code DPL 0, same base as SEL_CODE0
SEL_X_LDT   equ 0x40        ; LDT descriptor
SEL_X_TSS   equ 0x48        ; available 386 TSS
SEL_X_DATA0 equ 0x50        ; data DPL 0 (an SS-loadable descriptor)
; LDT (limit 0Fh: entries 0 and 1 inside)
LSEL_IN     equ 0x0F        ; entry 1, RPL 3: data DPL 3, inside the limit
LSEL_X_DATA equ 0x17        ; entry 2, RPL 3: data DPL 3, beyond
LSEL_X_CODE equ 0x1C        ; entry 3: code DPL 0, beyond
LSEL_X_STK  equ 0x24        ; entry 4: data DPL 0, beyond

R0_STACK    equ 0x8000

start:
    cli
    cld
    xor ax, ax                      ; linear 8: where LDT entry 1 is read
    mov es, ax                      ; through the reset LDT cache (base 0)
    mov dword [es:8], 0x0000FFFF    ; data DPL 3, base 10000h
    mov dword [es:12], 0x00CFF301
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, R0_STACK
    xor ebx, ebx
    xor ecx, ecx

; EXPECT_GP code, instruction: the instruction must raise #GP(code) at its own
; EIP with ESP unchanged; execution resumes after it.
%macro EXPECT_GP 2+
    inc ebx
    mov ebp, %1
    mov edi, %%resume
    mov dword [fault_eip], %%insn
    mov [saved_esp], esp
%%insn:
    %2
    jmp no_fault
%%resume:
    cmp ecx, ebx
    jne fail
%endmacro

; ---- a null LDTR (never loaded since reset): TI=1 has no table --------------
    mov ax, LSEL_IN
    EXPECT_GP LSEL_IN & 0xFFFC, mov gs, ax
    inc ebx
    mov eax, LSEL_IN
    lar eax, eax                            ; LAR: ZF=0, no fault
    jz fail

; ---- GDT: MOV / POP / Lxx data-segment loads --------------------------------
    EXPECT_GP SEL_X_DATA3, mov gs, [sel_x_data3]
    mov ax, gs
    cmp ax, SEL_DATA0
    jne fail
    EXPECT_GP SEL_X_DATA3, mov ds, [sel_x_data3]
    mov ax, ds
    cmp ax, SEL_DATA0
    jne fail
    mov eax, SEL_X_DATA3 | 3                ; RPL bits are cleared in the code
    EXPECT_GP SEL_X_DATA3, mov fs, ax
    mov ax, fs
    cmp ax, SEL_DATA0
    jne fail
    EXPECT_GP SEL_X_DATA0, mov ss, [sel_x_data0]
    mov ax, ss
    cmp ax, SEL_DATA0
    jne fail
    push dword SEL_X_DATA3
    EXPECT_GP SEL_X_DATA3, pop es
    add esp, 4
    mov ax, es
    cmp ax, SEL_DATA0
    jne fail
    push dword SEL_X_DATA0
    EXPECT_GP SEL_X_DATA0, pop ss
    add esp, 4
    EXPECT_GP SEL_X_DATA3, lds esi, [fp_x_data3]
    EXPECT_GP SEL_X_DATA3, les esi, [fp_x_data3]
    EXPECT_GP SEL_X_DATA3, lfs esi, [fp_x_data3]
    EXPECT_GP SEL_X_DATA3, lgs esi, [fp_x_data3]
    EXPECT_GP SEL_X_DATA0, lss esi, [fp_x_data0]
    mov ax, ss
    cmp ax, SEL_DATA0
    jne fail

; ---- GDT: CS loads ----------------------------------------------------------
    EXPECT_GP SEL_X_CODE, jmp SEL_X_CODE:escaped
    EXPECT_GP SEL_X_CODE, call SEL_X_CODE:escaped
    EXPECT_GP SEL_X_CODE, jmp far [fp_x_code]
    EXPECT_GP SEL_X_CODE, call far [fp_x_code]
    push dword SEL_X_CODE
    push dword escaped
    EXPECT_GP SEL_X_CODE, retf
    add esp, 8
    pushfd
    push dword SEL_X_CODE
    push dword escaped
    EXPECT_GP SEL_X_CODE, iretd
    add esp, 12
    ; a call gate inside the table whose target selector is beyond it
    EXPECT_GP SEL_X_CODE, jmp SEL_CGATE:0
    EXPECT_GP SEL_X_CODE, call SEL_CGATE:0
    ; an interrupt gate whose code selector is beyond the GDT (EXT = 0)
    EXPECT_GP SEL_X_CODE, int 0x30
    ; a TSS descriptor beyond the GDT (JMP to it would switch tasks)
    EXPECT_GP SEL_X_TSS, jmp SEL_X_TSS:0
    mov ax, cs
    cmp ax, SEL_CODE0
    jne fail

; ---- GDT: LLDT / LTR --------------------------------------------------------
    mov ax, SEL_X_LDT
    EXPECT_GP SEL_X_LDT, lldt ax
    sldt ax
    test ax, ax
    jnz fail
    mov ax, SEL_X_TSS
    EXPECT_GP SEL_X_TSS, ltr ax
    str ax
    test ax, ax
    jnz fail

; ---- a limit that ends inside a descriptor ----------------------------------
    lgdt [gdt_desc_partial]                 ; limit 33h: 30h-37h half inside
    EXPECT_GP SEL_X_DATA3, mov gs, [sel_x_data3]
    lgdt [gdt_desc]

; ---- in-limit boundary loads still work -------------------------------------
    inc ebx
    mov ax, SEL_DATA3 | 3
    mov gs, ax
    mov ax, gs
    cmp ax, SEL_DATA3 | 3
    jne fail

; ---- LDT (TI = 1) -----------------------------------------------------------
    mov ax, SEL_LDT
    lldt ax
    inc ebx
    mov ax, LSEL_IN                         ; last entry inside the LDT limit
    mov fs, ax
    mov ax, fs
    cmp ax, LSEL_IN
    jne fail
    mov ax, LSEL_X_DATA
    EXPECT_GP LSEL_X_DATA & 0xFFFC, mov gs, ax
    mov ax, gs
    cmp ax, SEL_DATA3 | 3
    jne fail
    EXPECT_GP LSEL_X_STK, mov ss, [lsel_x_stk]
    EXPECT_GP LSEL_X_CODE, jmp LSEL_X_CODE:escaped
    EXPECT_GP LSEL_X_DATA & 0xFFFC, lds esi, [fp_lx_data]
    mov ax, ds
    cmp ax, SEL_DATA0
    jne fail
    ; LLDT 0: the LDT just used is gone
    xor eax, eax
    lldt ax
    mov ax, LSEL_IN
    EXPECT_GP LSEL_IN & 0xFFFC, mov fs, ax
    mov ax, fs
    cmp ax, LSEL_IN                         ; loaded above, kept
    jne fail

    mov al, 0x01
    out STATUS_PORT, al
    hlt

no_fault:
escaped:
    mov eax, ebx
    jmp report

fail:
    mov eax, ebx
report:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

; #GP: check the error code, the faulting EIP and the frame's ESP, then resume.
gp_handler:
    cmp [esp], bp
    jne fail
    mov eax, [esp+4]
    cmp eax, [fault_eip]
    jne fail
    cmp word [esp+8], SEL_CODE0
    jne fail
    lea eax, [esp+16]
    cmp eax, [saved_esp]
    jne fail
    mov ecx, ebx
    mov esp, [saved_esp]
    jmp edi

%assign v 0
%rep 13
unexpected_%[v]:
    mov eax, 0x8000 + v
    jmp report
%assign v v+1
%endrep

align 4
fault_eip:   dd 0
saved_esp:   dd 0
sel_x_data3: dw SEL_X_DATA3
sel_x_data0: dw SEL_X_DATA0
lsel_x_stk:  dw LSEL_X_STK
fp_x_data3:  dd 0
             dw SEL_X_DATA3
fp_x_data0:  dd R0_STACK
             dw SEL_X_DATA0
fp_x_code:   dd escaped
             dw SEL_X_CODE
fp_lx_data:  dd 0
             dw LSEL_X_DATA

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF           ; 08: code DPL 0, base 10000h
    dq 0x00CF93010000FFFF           ; 10: data DPL 0, base 10000h
    dq 0x00CFF3010000FFFF           ; 18: data DPL 3, base 10000h
    dw ldt_end - ldt - 1            ; 20: LDT, limit 0Fh
    dw ldt
    db 0x01, 0x82, 0x00, 0x00
    dw escaped                      ; 28: 386 call gate DPL 0 -> 38h:escaped
    dw SEL_X_CODE
    db 0x00, 0x8C
    dw 0x0000
gdt_end:
    ; past the limit: descriptors that would load
    dq 0x00CFF3010000FFFF           ; 30: data DPL 3
    dq 0x00CF9B010000FFFF           ; 38: code DPL 0
    dw ldt_end - ldt - 1            ; 40: LDT
    dw ldt
    db 0x01, 0x82, 0x00, 0x00
    dw 0x0067                       ; 48: available 386 TSS
    dw tss
    db 0x01, 0x89, 0x00, 0x00
    dq 0x00CF93010000FFFF           ; 50: data DPL 0

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000
gdt_desc_partial:
    dw gdt_end - gdt - 1 + 4
    dd gdt + 0x10000

align 8
ldt:
    dq 0
    dq 0x00CFF3010000FFFF           ; 0C: data DPL 3 (inside)
ldt_end:
    dq 0x00CFF3010000FFFF           ; 14: data DPL 3 (beyond)
    dq 0x00CF9B010000FFFF           ; 1C: code DPL 0 (beyond)
    dq 0x00CF93010000FFFF           ; 24: data DPL 0 (beyond)

%macro GATE 2
    dw %1
    dw SEL_CODE0
    db 0, %2
    dw 0
%endmacro
align 8
idt:
%assign v 0
%rep 13
    GATE unexpected_%[v], 0x8E
%assign v v+1
%endrep
    GATE gp_handler, 0x8E           ; 0D
    times (0x30 - 14) dq 0
    dw escaped                      ; 30: interrupt gate -> 38h (beyond)
    dw SEL_X_CODE
    db 0, 0x8E
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    times 26 dd 0
