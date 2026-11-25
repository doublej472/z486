; idt_limit.asm - a protected-mode interrupt whose gate lies beyond the IDT limit
; raises #GP(vector*8+2+EXT)
;
; i486 PRM (Intel 240486), INT/INTO pseudo-code (p. 26-166), which "applies not
; only to the above instructions but also to external interrupts and
; exceptions":
;   PROTECTED-MODE:
;     Interrupt vector must be within IDT table limits,
;       else #GP(vector number * 8+2+EXT);
; 9.8 Error Code: "The processor sets the EXT bit if an event external to the
; program caused the exception" and "sets the IDT bit if the index portion of
; the error code refers to a gate descriptor in the IDT" (bit 1).  9.9.13 lists
; "Exceeding the segment limit when referencing a descriptor table" as #GP.
; 9.9.8 / Table 9-4: a contributory exception (#GP) raised while calling the
; handler of another contributory exception is a double fault.
;
; Every vector the test raises has a valid interrupt gate in the bytes just
; past the limit, so a CPU that reads it without the limit check enters a
; handler that fails the test.  z486 did: INT 20h with IDTR.limit 7Fh entered
; the gate at 100h.  Each case checks the #GP error code (low word; the upper
; half is a separate issue), the frame EIP, and that the frame ESP is the
; starting ESP (the interrupt pushed nothing).
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number
; (EBX) or 0x8000+n for an unexpected exception n.

BITS 16
org 0

STATUS_PORT        equ 0xE0
DATA_PORT          equ 0xE4
SIGNAL_PORT        equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_INSTR_PORT  equ 0xF0
SIGNAL_VECTOR_PORT equ 0xF4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10

R0_STACK    equ 0x8000

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc_7f]
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

; ---- INT n (software, EXT = 0), IDTR.limit 7Fh: vectors 00h-0Fh ------------
    EXPECT_GP 0x20*8+2, int 0x20
    EXPECT_GP 0x10*8+2, int 0x10            ; first vector past the limit
    EXPECT_GP 0xFF*8+2, int 0xFF
    ; a gate inside the limit whose type is not a gate: the same error code
    EXPECT_GP 0x0F*8+2, int 0x0F

; ---- a limit that ends inside the gate --------------------------------------
    lidt [idt_desc_83]                      ; 80h-83h inside, 84h-87h beyond
    EXPECT_GP 0x10*8+2, int 0x10
    lidt [idt_desc_86]                      ; the last byte beyond
    EXPECT_GP 0x10*8+2, int 0x10

; ---- the boundary gate inside the limit is taken ----------------------------
    lidt [idt_desc_87]
    inc ebx
    mov dword [ok_count], 0
    int 0x10
    cmp dword [ok_count], 1
    jne fail
    lidt [idt_desc_7f]

; ---- external interrupt (EXT = 1): vector 20h past the limit ----------------
    inc ebx
    mov ebp, 0x20*8+3
    mov edi, .intr_resume
    mov dword [fault_eip], .spin
    mov [saved_esp], esp
    mov dx, SIGNAL_VECTOR_PORT
    mov al, 0x20
    out dx, al
    mov dx, SIGNAL_INSTR_PORT
    xor ax, ax                              ; cycle-delay mode
    out dx, ax
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 40
    out dx, ax
    mov dx, SIGNAL_PORT
    mov al, 1                               ; request INTR
    out dx, al
    sti
.spin:
    jmp .spin                               ; one instruction: the frame EIP
.intr_resume:
    cli
    cmp ecx, ebx
    jne fail

; ---- #GP's own gate past the limit: the second #GP is a double fault --------
    lidt [idt_desc_67]                      ; vectors 00h-0Ch: #DF inside, #GP not
    inc ebx
    mov edi, .df_resume
    mov [saved_esp], esp
    int 0x20
    jmp no_fault
.df_resume:
    cmp ecx, ebx
    jne fail
    lidt [idt_desc_7f]

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

; #DF: error code 0 (9.9.8), then resume.
df_handler:
    cmp word [esp], 0
    jne fail
    mov ecx, ebx
    mov esp, [saved_esp]
    jmp edi

ok_handler:
    inc dword [ok_count]
    iretd

%assign v 0
%rep 16
unexpected_%[v]:
    mov eax, 0x8000 + v
    jmp report
%assign v v+1
%endrep

align 4
fault_eip:   dd 0
saved_esp:   dd 0
ok_count:    dd 0

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF           ; 08: code DPL 0, base 10000h
    dq 0x00CF93010000FFFF           ; 10: data DPL 0, base 10000h
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
%assign v 0
%rep 8
    GATE unexpected_%[v], 0x8E      ; 00-07
%assign v v+1
%endrep
    GATE df_handler, 0x8E           ; 08
%assign v 9
%rep 4
    GATE unexpected_%[v], 0x8E      ; 09-0C
%assign v v+1
%endrep
    GATE gp_handler, 0x8E           ; 0D
    GATE unexpected_14, 0x8E        ; 0E
    GATE unexpected_15, 0x00        ; 0F: not a gate (type 0, not present)
    ; past limit 7Fh: valid gates a CPU without the check would enter
    GATE ok_handler, 0xEE           ; 10 (DPL 3; the in-limit control enters it)
%rep (0x100 - 0x11)
    GATE escaped, 0xEE
%endrep

idt_desc_7f:
    dw 0x7F
    dd idt + 0x10000
idt_desc_83:
    dw 0x83
    dd idt + 0x10000
idt_desc_86:
    dw 0x86
    dd idt + 0x10000
idt_desc_87:
    dw 0x87
    dd idt + 0x10000
idt_desc_67:
    dw 0x67
    dd idt + 0x10000
