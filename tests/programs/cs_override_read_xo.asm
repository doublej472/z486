; cs_override_read_xo.asm - a data read through CS from an execute-only code
; segment raises #GP(0)
;
; i486 PRM (Intel 240486), 6.2.1 Type Checking: "No instruction may read an
; executable segment unless the readable bit is set"; a readable executable
; segment "may be read in two ways: 1. With the CS register, by using a CS
; override prefix" (6.2.1, and 6.3.1 case 3).  9.9.13 Interrupt 13 lists
; "Reading from an execute-only code segment" among the general-protection
; exceptions; the error code is null (no descriptor is being loaded).
;
; z486 checked the R bit on its direct-load path (which then hands the access
; to the microcode) but its microcode segment check treated CS as always
; readable, so every one of these reads returned the code bytes.
;
; Phase 1 runs in an execute-only CPL0 code segment (08h, access 98h, type
; 1000b).  Each read through CS must raise exactly one #GP(0) at its own EIP
; with ESP unchanged, the destination register or memory and the string
; registers unchanged.  A write through CS raises #GP(0) as before.  Phase 2
; runs the same reads from a readable alias (18h, access 9Ah) and checks the
; values read; the write still raises #GP(0) there.  DS (10h) is a data alias
; of the same bytes, so the handler and the checks never read through CS.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number
; (EBX) or 0x8000+n for an unexpected exception n.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_XO      equ 0x08        ; code DPL 0, execute-only, base 10000h
SEL_DATA0   equ 0x10        ; data DPL 0, base 10000h
SEL_RX      equ 0x18        ; code DPL 0, execute/read, base 10000h

R0_STACK    equ 0x8000
JUNK        equ 0xA5A5A5A5
VALUE       equ 0x12345678

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp dword SEL_XO:pm

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
    mov dword [resume_cs], SEL_XO

; EXPECT_GP instruction: the instruction must raise #GP(0) at its own EIP with
; ESP unchanged; execution resumes after it (in the code segment named by
; [resume_cs]).  The handler counts the #GPs in [gp_seen].
%macro EXPECT_GP 1+
    inc ebx
    mov dword [resume_eip], %%resume
    mov dword [fault_eip], %%insn
    mov dword [gp_seen], 0
    mov [saved_esp], esp
%%insn:
    %1
    jmp no_fault
%%resume:
    cmp dword [gp_seen], 1
    jne fail
%endmacro

%macro CHECK_EAX 1
    cmp eax, %1
    jne fail
%endmacro

; ---- phase 1: execute-only CS -----------------------------------------------
    mov eax, JUNK
    EXPECT_GP mov eax, [cs:var]             ; moffs form (A1)
    CHECK_EAX JUNK
    mov edx, var
    EXPECT_GP mov eax, [cs:edx]             ; ModR/M form
    CHECK_EAX JUNK
    EXPECT_GP add eax, [cs:edx]
    CHECK_EAX JUNK
    EXPECT_GP movzx eax, byte [cs:edx]
    CHECK_EAX JUNK
    EXPECT_GP imul eax, [cs:edx], 3
    CHECK_EAX JUNK
    EXPECT_GP cmp [cs:edx], al
    EXPECT_GP bt dword [cs:edx], 0
    EXPECT_GP push dword [cs:edx]
    EXPECT_GP jmp dword [cs:near_ptr]
    EXPECT_GP call dword [cs:near_ptr]
    mov esi, JUNK
    EXPECT_GP les esi, [cs:far_ptr]
    cmp esi, JUNK
    jne fail
    mov ax, es
    cmp ax, SEL_DATA0
    jne fail
    ; string sources with a CS override
    mov esi, var
    mov edi, dst
    mov dword [dst], JUNK
    EXPECT_GP cs movsb
    call check_string
    EXPECT_GP cs movsd
    call check_string
    mov eax, JUNK
    EXPECT_GP cs lodsd
    CHECK_EAX JUNK
    call check_string
    EXPECT_GP cs cmpsb
    call check_string
    mov ecx, 4
    EXPECT_GP rep cs movsb
    cmp ecx, 4
    jne fail
    call check_string
    inc ebx
    mov ebp, ebx                            ; XLAT addresses [EBX]
    mov ebx, table
    mov eax, JUNK
    EXPECT_GP cs xlatb
    mov ebx, ebp
    CHECK_EAX JUNK
    ; a write through CS is #GP(0) as before
    EXPECT_GP mov [cs:edx], eax
    cmp dword [var], VALUE
    jne fail

; ---- phase 2: the same reads from a readable code segment --------------------
    jmp SEL_RX:phase2
phase2:
    mov dword [resume_cs], SEL_RX
    inc ebx
    mov edx, var
    mov eax, [cs:var]
    CHECK_EAX VALUE
    mov eax, [cs:edx]
    CHECK_EAX VALUE
    add eax, [cs:edx]
    CHECK_EAX VALUE * 2
    movzx eax, byte [cs:edx]
    CHECK_EAX VALUE & 0xFF
    imul eax, [cs:edx], 3
    CHECK_EAX (VALUE * 3) & 0xFFFFFFFF
    cmp [cs:edx], al
    bt dword [cs:edx], 3                    ; bit 3 of 78h is 1
    jnc fail
    push dword [cs:edx]
    pop eax
    CHECK_EAX VALUE
    inc ebx
    mov dword [near_ptr], .jmp_ok
    jmp dword [cs:near_ptr]
    jmp fail
.jmp_ok:
    les esi, [cs:far_ptr]
    cmp esi, var
    jne fail
    mov ax, es
    cmp ax, SEL_DATA0
    jne fail
    inc ebx
    mov esi, var
    mov edi, dst
    mov dword [dst], JUNK
    cs movsd
    cmp dword [dst], VALUE
    jne fail
    mov esi, var
    cs lodsd
    CHECK_EAX VALUE
    mov ebp, ebx
    mov ebx, table
    mov eax, 2
    cs xlatb
    mov ebx, ebp
    CHECK_EAX 0x22
    EXPECT_GP mov [cs:edx], eax
    cmp dword [var], VALUE
    jne fail

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; the string registers and the destination are unchanged
check_string:
    cmp esi, var
    jne fail
    cmp edi, dst
    jne fail
    cmp dword [dst], JUNK
    jne fail
    ret

no_fault:
    mov eax, ebx
    jmp report

fail:
    mov eax, ebx
report:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

; #GP: check the error code, the faulting EIP and CS and the frame's ESP, then
; resume after the instruction in the phase's code segment.
gp_handler:
    mov [saved_eax], eax                    ; the cases check EAX after it
    inc dword [gp_seen]
    cmp word [esp], 0
    jne fail
    mov eax, [esp+4]
    cmp eax, [fault_eip]
    jne fail
    mov eax, [esp+8]
    cmp ax, [resume_cs]
    jne fail
    lea eax, [esp+16]
    cmp eax, [saved_esp]
    jne fail
    mov esp, [saved_esp]
    push dword [resume_cs]
    push dword [resume_eip]
    mov eax, [saved_eax]
    retf

%assign v 0
%rep 13
unexpected_%[v]:
    mov eax, 0x8000 + v
    jmp report
%assign v v+1
%endrep

align 4
var:         dd VALUE
dst:         dd 0
near_ptr:    dd no_fault
far_ptr:     dd var
             dw SEL_DATA0
table:       db 0x00, 0x11, 0x22, 0x33
fault_eip:   dd 0
saved_esp:   dd 0
resume_cs:   dd 0
resume_eip:  dd 0
gp_seen:     dd 0
saved_eax:   dd 0

align 8
gdt:
    dq 0
    dq 0x00CF98010000FFFF           ; 08: code DPL 0, execute-only, base 10000h
    dq 0x00CF93010000FFFF           ; 10: data DPL 0, base 10000h
    dq 0x00CF9A010000FFFF           ; 18: code DPL 0, execute/read, base 10000h
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

%macro GATE 2
    dw %1
    dw SEL_XO
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
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000
