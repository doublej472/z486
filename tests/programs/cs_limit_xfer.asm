; cs_limit_xfer.asm - a transfer to an offset beyond the CS limit faults at the transfer
;
; i486 Programmer's Reference Manual: JMP, CALL, RET, IRET and INT n check
; the new instruction pointer against the code segment limit as a step of
; the instruction ("Instruction pointer must be in code segment limit ELSE
; #GP(0)", CALL operation, p. 26-46; INT n: "Instruction pointer must be in
; CS limit, else #GP(0)", p. 26-169; CALL Protected Mode Exceptions,
; p. 26-49: "For near direct calls: #GP(0) if procedure location is beyond
; the code segment limits ... #GP(0) if the indirect offset obtained is
; beyond the code segment limits"; JMP, p. 26-186, the same for near jumps).
; The #GP is that instruction's fault, so
; (9.1, p. 9-2) "the return address for the fault handler points to the
; instruction which generated the fault" and (9.2, p. 9-3) "the processor
; registers are restored to the state they held before execution of the
; instruction began": the frame names the transfer, ESP is the value before
; it (a CALL has pushed nothing, a RET / RETF / IRETD popped nothing), and the
; error code is 0 (9.9.13, p. 9-21: no descriptor caused it).
;
; Selector 18h: code32, base 10000h, limit 1FF7h.  Every target is 3000h
; (BEYOND); its bytes (MOV EBX,0BADh) are first run through the flat selector
; 08h so the line is cached.  Far forms run in selector 08h; near forms run
; in stubs inside selector 18h; INT n, INT3 and #UD use interrupt gates to
; 18h:3000h.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4:
; (case << 8) | check.  Checks: 1 exactly one #GP, 2 error code (low word;
; not judged for the #UD delivery, whose EXT bit is a separate question),
; 3 frame EIP = the transfer, 4 frame CS, 5 ESP before the fault = ESP
; before the transfer, 6 EBX (the target ran).

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08    ; code32, base 10000h, 4 GB
SEL_DATA0   equ 0x10    ; data32, base 10000h, 4 GB
SEL_LIM     equ 0x18    ; code32, base 10000h, limit 1FF7h

BEYOND      equ 0x3000
STACK_TOP   equ 0x6000
NO_EC       equ 0x80000000  ; case flag: do not judge the error code

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
    mov esp, STACK_TOP
    jmp cases

; %1 case id (| NO_EC), %2 the frame CS expected.
%macro XBEGIN 2
    mov dword [case_id], %1
    mov dword [exp_cs], %2
    mov dword [resume], %%next
    mov dword [got], 0
    mov dword [got_ec], 0xEEEEEEEE
    mov dword [got_eip], 0xEEEEEEEE
    mov dword [got_cs], 0xEEEEEEEE
    mov dword [got_esp], 0xEEEEEEEE
    mov dword [ebx_seen], 0xEEEEEEEE
    mov esp, STACK_TOP
    call BEYOND                 ; through selector 08h: fills the cache
    xor ebx, ebx
    mov eax, BEYOND
    mov dword [nearptr], BEYOND
    mov dword [farptr], BEYOND
    mov word [farptr + 4], SEL_LIM
%define XNEXT %%next
%endmacro

; Immediately before the transfer instruction: record its offset and ESP.
%macro XAT 0
    mov dword [exp_eip], %%x
    mov [exp_esp], esp
%%x:
%endmacro

%macro XEND 0
XNEXT:
    call check
%undef XNEXT
%endmacro

; A near form: enter stub %2 in selector 18h with a (legal) far JMP.
%macro NEARCASE 2
    XBEGIN %1, SEL_LIM
    jmp SEL_LIM:%2
    XEND
%endmacro

cases:
    XBEGIN 0x00, SEL_CODE0
    XAT
    jmp SEL_LIM:BEYOND
    XEND

    XBEGIN 0x01, SEL_CODE0
    XAT
    call SEL_LIM:BEYOND
    XEND

    XBEGIN 0x02, SEL_CODE0
    XAT
    jmp far [farptr]
    XEND

    XBEGIN 0x03, SEL_CODE0
    XAT
    call far [farptr]
    XEND

    XBEGIN 0x04, SEL_CODE0
    push dword SEL_LIM
    push dword BEYOND
    XAT
    retf
    XEND

    XBEGIN 0x05, SEL_CODE0
    pushfd
    push dword SEL_LIM
    push dword BEYOND
    XAT
    iretd
    XEND

    XBEGIN 0x06, SEL_CODE0
    XAT
    int 0x41
    XEND

    XBEGIN 0x07, SEL_CODE0
    XAT
    int3
    XEND

    XBEGIN 0x08 | NO_EC, SEL_CODE0
    XAT
    ud2
    XEND

    NEARCASE 0x10, n_jmp
    NEARCASE 0x11, n_call
    NEARCASE 0x12, n_jcc
    NEARCASE 0x13, n_jmpr
    NEARCASE 0x14, n_callr
    NEARCASE 0x15, n_jmpm
    NEARCASE 0x16, n_callm
    NEARCASE 0x17, n_ret
    NEARCASE 0x18, n_retimm
    NEARCASE 0x19, n_jmp8
    NEARCASE 0x1A, n_jcc8
    NEARCASE 0x1B, n_loop
    NEARCASE 0x1C, n_jecxz

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; The near stubs (selector 18h, offsets within its limit).  EAX and
; [nearptr] hold the target.
n_jmp:    XAT
          jmp BEYOND
n_call:   XAT
          call BEYOND
n_jcc:    cmp eax, eax
          XAT
          je near BEYOND
          jmp fail_fallthrough
n_jmpr:   XAT
          jmp eax
n_callr:  XAT
          call eax
n_jmpm:   XAT
          jmp dword [nearptr]
n_callm:  XAT
          call dword [nearptr]
n_ret:    push eax
          XAT
          ret
n_retimm: push eax
          XAT
          ret 8
; The short forms reach past the limit from just below it.
n_jmp8:   jmp near1
n_jcc8:   jmp near2
n_loop:   jmp near3
n_jecxz:  jmp near4

fail_fallthrough:
    jmp SEL_CODE0:fail_ft0
fail_ft0:
    mov edx, 0xF0
    jmp fail

check:
    mov edx, [case_id]
    and edx, 0xFF
    shl edx, 8
    inc edx
    cmp dword [got], 1
    jne fail
    inc edx
    test dword [case_id], NO_EC
    jnz .ec_ok
    cmp word [got_ec], 0
    jne fail
.ec_ok:
    inc edx
    mov eax, [exp_eip]
    cmp [got_eip], eax
    jne fail
    inc edx
    mov eax, [exp_cs]
    cmp [got_cs], eax
    jne fail
    inc edx
    mov eax, [exp_esp]
    cmp [got_esp], eax
    jne fail
    inc edx
    cmp dword [ebx_seen], 0
    jne fail
    ret

fail:
    mov eax, edx
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

isr_gp:
    mov [ss:ebx_seen], ebx
    lea eax, [esp + 16]         ; ESP before the fault (same-level gate)
    mov [ss:got_esp], eax
    pop dword [ss:got_ec]
    mov eax, [esp]
    mov [ss:got_eip], eax
    movzx eax, word [esp + 4]
    mov [ss:got_cs], eax
    inc dword [ss:got]
    mov eax, [ss:resume]
    mov [esp], eax
    mov dword [esp + 4], SEL_CODE0
    iretd

isr_other:
    mov edx, [ss:case_id]
    and edx, 0xFF
    shl edx, 8
    or edx, 0xEF
    jmp SEL_CODE0:fail

;==================================================================
align 4
case_id:  dd 0
resume:   dd 0
got:      dd 0
got_ec:   dd 0
got_eip:  dd 0
got_cs:   dd 0
got_esp:  dd 0
exp_eip:  dd 0
exp_cs:   dd 0
exp_esp:  dd 0
ebx_seen: dd 0
nearptr:  dd 0
farptr:   dd 0
          dw 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code32, 4 GB
    dq 0x00CF93010000FFFF       ; 0x10 data32, 4 GB
    dq 0x00409B0100001FF7       ; 0x18 code32, limit 1FF7h
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro IGATE 2
    dw %1
    dw %2
    db 0
    db 10001110b
    dw 0
%endmacro

align 8
idt:
%rep 3
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE BEYOND, SEL_LIM       ; 3 (INT3)
%rep 2
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE BEYOND, SEL_LIM       ; 6 (#UD)
%rep 6
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE isr_gp, SEL_CODE0     ; 13
%rep 0x41 - 14
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE BEYOND, SEL_LIM       ; 41h
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

; Short transfers from just below the limit (1FF7h) to just beyond it.
    times 0x1F70 - ($ - $$) db 0xCC
near1:    XAT
          jmp short 0x1FF8
near2:    cmp eax, eax
          XAT
          je short 0x1FFC
          jmp fail_fallthrough
near3:    mov ecx, 2
          XAT
          loop 0x2000
          jmp fail_fallthrough
near4:    xor ecx, ecx
          XAT
          jecxz 0x2004
          jmp fail_fallthrough
    times 0x1FF8 - ($ - $$) db 0xCC
    times 0x2010 - ($ - $$) db 0x90     ; beyond 18h's limit: must not run
    mov ebx, 0xBAD
    ret

; The target.  Through selector 08h it runs and returns (the cache fill);
; through selector 18h it must never run.
    times BEYOND - ($ - $$) db 0xCC
    mov ebx, 0xBAD
    ret
