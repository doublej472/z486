; outer_ret_ss_fault.asm - a return to an outer level whose new SS is invalid
;
; i486 PRM, RET (return to outer privilege level) and IRET (return to outer
; privilege level) check the return SS selector and its descriptor BEFORE
; "Set CPL to the RPL of the return CS selector" and the loads of CS:EIP and
; SS:ESP:
;
;   Selector must be non-null, else #GP(0)
;   Selector index must be within its descriptor table limits, else #GP(selector)
;   Selector RPL must equal the RPL of the return CS selector, else #GP(selector)
;   Descriptor AR byte must indicate a writable data segment, else #GP(selector)
;   Descriptor DPL must equal the RPL of the return CS selector, else #GP(selector)
;   Segment must be present, else #SS(selector)
;
; A fault there is therefore raised at the old CPL 0: same-privilege delivery
; on the current stack (no TSS stack switch), frame CS = the ring-0 selector,
; frame EIP = the RET/IRET (a fault frame names the faulting instruction),
; and the handler's ESP is the instruction-start ESP minus the 16-byte frame
; of a 32-bit gate (EFLAGS, CS, EIP, error code).  The not-present return CS
; case (#NP(selector), checked before SS) is covered alongside.
;
; Each check runs for o32 RETF, o16 RETF, o32 RETF imm16, o16 RETF imm16,
; IRETD and o16 IRET.  The TSS's ring-0 stack is elsewhere (TSS_ESP0), so a
; delivery that wrongly switches stacks is seen in the handler's ESP.
; After every faulting case the code runs on at CPL 0 (a MOV to CR0 and a
; ring-0 data segment load would fault at CPL 3).  Last, after a failing
; LAR, one valid RETF reaches ring 3 to show the path itself works.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code:
; (case << 8) | check.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18    ; DPL 3 code (accessed bit preset)
SEL_DATA3   equ 0x20    ; DPL 3 writable data
SEL_TSS     equ 0x28
SEL_CODE3NP equ 0x30    ; DPL 3 code, not present
SEL_RODATA3 equ 0x38    ; DPL 3 read-only data
SEL_DATA3NP equ 0x40    ; DPL 3 writable data, not present
SEL_DATA2   equ 0x48    ; DPL 2 writable data
SEL_BEYOND  equ 0x50    ; first selector past the GDT limit

STACK0_TOP  equ 0x6000  ; the stack every case runs on
TSS_ESP0    equ 0x5000  ; TSS SS0:ESP0, must stay unused
STACK3_TOP  equ 0x7000

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
    mov es, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax
    pushfd                      ; IOPL 3: ring-3 code may report
    or dword [esp], 0x3000
    popfd
    jmp cases

; ---------------------------------------------------------------------------
; One case.  %1 id, %2 form, %3 return SS, %4 return CS, %5 vector, %6 error code
; Forms: 0 o32 RETF, 1 o16 RETF, 2 o32 RETF 8, 3 o16 RETF 4, 4 IRETD, 5 o16 IRET
%macro RCASE 6
    mov dword [case_id], %1
    mov dword [exp_vec], %5
    mov dword [exp_ec], %6
    mov dword [exp_eip], %%insn
    mov dword [resume], %%next
    mov dword [got_vec], 0
%if %2 == 0
    push dword %3
    push dword STACK3_TOP
    push dword %4
    push dword ring3_land
%elif %2 == 1
    push word %3
    push word STACK3_TOP
    push word %4
    push word ring3_land
%elif %2 == 2
    push dword %3
    push dword STACK3_TOP
    push dword 0x11111111
    push dword 0x22222222
    push dword %4
    push dword ring3_land
%elif %2 == 3
    push word %3
    push word STACK3_TOP
    push word 0x3333
    push word 0x4444
    push word %4
    push word ring3_land
%elif %2 == 4
    push dword %3
    push dword STACK3_TOP
    push dword 0x00003002
    push dword %4
    push dword ring3_land
%else
    push word %3
    push word STACK3_TOP
    push word 0x3002
    push word %4
    push word ring3_land
%endif
    mov [exp_esp], esp
%%insn:
%if %2 == 0
    retf
%elif %2 == 1
    o16 retf
%elif %2 == 2
    retf 8
%elif %2 == 3
    o16 retf 4
%elif %2 == 4
    iretd
%else
    o16 iret
%endif
%%next:
    mov ebx, (%1 << 8) | 0x10
    cmp dword [got_vec], %5     ; the handler ran
    jne fail
    mov ebx, (%1 << 8) | 0x11
    mov ax, cs                  ; still ring 0
    cmp ax, SEL_CODE0
    jne fail
    mov ebx, (%1 << 8) | 0x12
    mov ax, ss
    cmp ax, SEL_DATA0
    jne fail
    mov eax, cr0                ; privileged: #GP at CPL 3
    mov ax, SEL_DATA0           ; DPL 0 data: #GP at CPL 3
    mov ds, ax
    mov esp, STACK0_TOP
%endmacro

; Every SS fault class plus the not-present CS, for one form.  %1 form.
%macro RFORM 1
    RCASE (%1*16+0), %1, 0,                 SEL_CODE3 | 3,   13, 0
    RCASE (%1*16+1), %1, SEL_BEYOND | 3,    SEL_CODE3 | 3,   13, SEL_BEYOND
    RCASE (%1*16+2), %1, SEL_DATA0,         SEL_CODE3 | 3,   13, SEL_DATA0
    RCASE (%1*16+3), %1, SEL_DATA3 | 2,     SEL_CODE3 | 3,   13, SEL_DATA3
    RCASE (%1*16+4), %1, SEL_CODE3 | 3,     SEL_CODE3 | 3,   13, SEL_CODE3
    RCASE (%1*16+5), %1, SEL_RODATA3 | 3,   SEL_CODE3 | 3,   13, SEL_RODATA3
    RCASE (%1*16+6), %1, SEL_DATA0 | 3,     SEL_CODE3 | 3,   13, SEL_DATA0
    RCASE (%1*16+7), %1, SEL_DATA2 | 3,     SEL_CODE3 | 3,   13, SEL_DATA2
    RCASE (%1*16+8), %1, SEL_DATA3NP | 3,   SEL_CODE3 | 3,   12, SEL_DATA3NP
    RCASE (%1*16+9), %1, SEL_DATA3 | 3,     SEL_CODE3NP | 3, 11, SEL_CODE3NP
%endmacro

cases:
    RFORM 0
    RFORM 1
    RFORM 2
    RFORM 3
    RFORM 4
    RFORM 5
    ; a valid return to ring 3, after a failing LAR (its probe runs through
    ; the exception-entry microcode without raising a fault, which must not
    ; count as one)
    mov dword [case_id], 0xF0
    mov ax, SEL_BEYOND
    lar eax, ax
    mov ebx, 0xF0F0
    jz fail
    mov dword [resume], fail_unexpected
    push dword SEL_DATA3 | 3
    push dword STACK3_TOP
    push dword SEL_CODE3 | 3
    push dword ring3_pass
    retf

; Ring 3: a faulting case must never get here.
ring3_land:
    mov ebx, [cs:case_id]
    shl ebx, 8
    or ebx, 0xAA
    jmp r3_fail

ring3_pass:
    mov ax, cs
    mov ebx, 0xF001
    cmp ax, SEL_CODE3 | 3
    jne r3_fail
    mov ax, ss
    mov ebx, 0xF002
    cmp ax, SEL_DATA3 | 3
    jne r3_fail
    mov ebx, 0xF003
    cmp esp, STACK3_TOP
    jne r3_fail
    mov dx, STATUS_PORT
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

; Ring 0 failure report (DS may be anything: SS is the ring-0 data segment)
fail:
    mov eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp fail

fail_unexpected:
    mov ebx, [ss:case_id]
    shl ebx, 8
    or ebx, 0xEE
    jmp fail

; ---------------------------------------------------------------------------
; Handlers (32-bit interrupt gates to SEL_CODE0).  Frame: [esp] error code,
; [esp+4] EIP, [esp+8] CS, [esp+12] EFLAGS.
isr_np:
    mov dword [ss:got_vec], 11
    jmp isr_check
isr_ss:
    mov dword [ss:got_vec], 12
    jmp isr_check
isr_gp:
    mov dword [ss:got_vec], 13
isr_check:
    mov ebx, [ss:case_id]
    shl ebx, 8
    mov bl, 1
    mov eax, [ss:got_vec]
    cmp eax, [ss:exp_vec]
    jne fail
    mov bl, 2                   ; same stack: no switch to SS0:ESP0
    mov ax, ss
    cmp ax, SEL_DATA0
    jne fail
    mov bl, 3                   ; instruction-start ESP minus the frame
    lea eax, [esp + 16]
    cmp eax, [ss:exp_esp]
    jne fail
    mov bl, 4                   ; error code: low word (this test does not
    movzx eax, word [esp]       ; judge the upper half of the push)
    cmp eax, [ss:exp_ec]
    jne fail
    mov bl, 5
    mov eax, [esp + 4]
    cmp eax, [ss:exp_eip]
    jne fail
    mov bl, 6                   ; delivered from CPL 0
    movzx eax, word [esp + 8]
    cmp eax, SEL_CODE0
    jne fail
    mov bl, 7
    mov ax, cs
    cmp ax, SEL_CODE0
    jne fail
    mov eax, [ss:resume]
    mov [esp + 4], eax
    add esp, 4
    iretd

isr_other:
    mov ebx, [ss:case_id]
    shl ebx, 8
    or ebx, 0xEF
    jmp fail

;==================================================================
align 4
case_id: dd 0
exp_vec: dd 0
exp_ec:  dd 0
exp_eip: dd 0
exp_esp: dd 0
resume:  dd 0
got_vec: dd 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0
    dq 0x00CF93010000FFFF       ; 0x10 data0
    dq 0x00CFFB010000FFFF       ; 0x18 code3 (readable, accessed)
    dq 0x00CFF3010000FFFF       ; 0x20 data3
    dw 0x0067                   ; 0x28 TSS
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    dq 0x00CF7B010000FFFF       ; 0x30 code3, not present
    dq 0x00CFF1010000FFFF       ; 0x38 data3, read-only
    dq 0x00CF73010000FFFF       ; 0x40 data3, not present
    dq 0x00CFD3010000FFFF       ; 0x48 data DPL 2
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro IGATE 1
    dw %1
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
%rep 11
    IGATE isr_other
%endrep
    IGATE isr_np                ; 11
    IGATE isr_ss                ; 12
    IGATE isr_gp                ; 13
%rep 18
    IGATE isr_other
%endrep
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss386:
    dd 0
    dd TSS_ESP0
    dd SEL_DATA0
    times 22 dd 0
    dw 0
    dw 104
