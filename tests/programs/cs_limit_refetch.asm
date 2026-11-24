; cs_limit_refetch.asm - a transfer's target is decoded against the NEW CS:EIP's limit
;
; i486 Programmer's Reference Manual: an instruction any byte of which lies
; beyond the code-segment limit is not executed; fetching it raises #GP(0)
; (9.8.13, Interrupt 13 - General Protection: "exceeding the segment limit
; when using CS ..."), and a transfer's target is checked against the new
; limit (JMP / CALL / RET / IRET / INT n pseudo-code: "IF instruction pointer
; not within code segment limit THEN #GP(0)").
;
; Each case first executes the target bytes through the flat selector 08h, so
; their lines are resident in the code cache, then reaches the same linear
; bytes through selector 18h (same base, limit 1FF7h):
;
;   - STRADDLE (1FF5h): MOV EBX,0BADh, 5 bytes, crosses the limit.  The
;     transfer itself is legal; the instruction there faults: #GP(0) with the
;     frame CS:EIP = 0018h:1FF5h, and EBX stays 0.
;   - BEYOND (3000h): the target offset is beyond the limit.  #GP(0) and EBX
;     stays 0.  The frame's EIP and the stack are not checked here: whether
;     the fault names the transfer or the target is a separate question.
;
; Transfers: far JMP ptr16:32, far CALL ptr16:32, far JMP m16:32, RETF,
; IRETD, INT n, INT3 and a #UD delivery (interrupt gates into 18h), and
; inside selector 18h: JMP rel32, CALL rel32, Jcc rel32, JMP EAX, CALL EAX,
; JMP m32 and RET.
;
; The #GP's error code is not judged here: a fetch-limit #GP taken with the
; microcode idle pushes a stale value in place of 0, a separate fault-entry
; defect that a sequential run off the limit shows as well.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4:
; (case << 8) | check.  Checks: 1 exactly one #GP, 2 EBX (the target
; executed), 3 frame EIP, 4 frame CS.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08    ; code32, base 10000h, 4 GB
SEL_DATA0   equ 0x10    ; data32, base 10000h, 4 GB
SEL_LIM     equ 0x18    ; code32, base 10000h, limit 1FF7h (byte granular)

LIMIT       equ 0x1FF7
STRADDLE    equ 0x1FF5  ; 5-byte instruction at 1FF5h-1FF9h
BEYOND      equ 0x3000
STACK_TOP   equ 0x6000

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

; ---------------------------------------------------------------------------
; %1 case id, %2 target (STRADDLE / BEYOND), then the transfer's code lines.
%macro XBEGIN 2
    mov dword [case_id], %1
    mov dword [target], %2
    mov dword [resume], %%next
    mov dword [got], 0
    mov dword [got_ec], 0xEEEEEEEE
    mov dword [got_eip], 0xEEEEEEEE
    mov dword [got_cs], 0xEEEEEEEE
    mov esp, STACK_TOP
    call %2                     ; through selector 08h: fills the cache
    xor ebx, ebx
    mov eax, %2
    mov dword [nearptr], %2
    mov dword [farptr], %2
    mov word [farptr + 4], SEL_LIM
%define XNEXT %%next
%endmacro

%macro XEND 0
XNEXT:
    call check
%undef XNEXT
%endmacro

; One far form, %1 base id: the transfer code is the macro body %2.
%macro FARCASES 2
    XBEGIN %1, STRADDLE
    %2 STRADDLE, 0x40
    XEND
    XBEGIN %1 + 1, BEYOND
    %2 BEYOND, 0x41
    XEND
%endmacro

%macro T_JMPF 2
    jmp SEL_LIM:%1
%endmacro
%macro T_CALLF 2
    call SEL_LIM:%1
%endmacro
%macro T_JMPFM 2
    jmp far [farptr]
%endmacro
%macro T_RETF 2
    push dword SEL_LIM
    push dword %1
    retf
%endmacro
%macro T_IRETD 2
    pushfd
    push dword SEL_LIM
    push dword %1
    iretd
%endmacro
%macro T_INT 2
    int %2
%endmacro
; Near forms run in selector 18h: enter its stub with a far JMP (legal).
%macro T_NEAR 2
    jmp SEL_LIM:%2
%endmacro

cases:
    FARCASES 0x00, T_JMPF
    FARCASES 0x02, T_CALLF
    FARCASES 0x04, T_JMPFM
    FARCASES 0x06, T_RETF
    FARCASES 0x08, T_IRETD
    FARCASES 0x0A, T_INT

    ; Exception deliveries: INT3 through the gate 18h:STRADDLE, #UD through
    ; the gate 18h:BEYOND.
    XBEGIN 0x0C, STRADDLE
    int3
    XEND
    XBEGIN 0x0D, BEYOND
    ud2
    XEND

%macro NEARCASES 3
    XBEGIN %1, STRADDLE
    jmp SEL_LIM:%2
    XEND
    XBEGIN %1 + 1, BEYOND
    jmp SEL_LIM:%3
    XEND
%endmacro

    NEARCASES 0x10, n_jmp_s,   n_jmp_b
    NEARCASES 0x12, n_call_s,  n_call_b
    NEARCASES 0x14, n_jcc_s,   n_jcc_b
    NEARCASES 0x16, n_jmpr,    n_jmpr
    NEARCASES 0x18, n_callr,   n_callr
    NEARCASES 0x1A, n_jmpm,    n_jmpm
    NEARCASES 0x1C, n_ret,     n_ret

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; The near stubs (selector 18h, offsets within its limit).  EAX and
; [nearptr] hold the target.
n_jmp_s:  jmp STRADDLE
n_jmp_b:  jmp BEYOND
n_call_s: call STRADDLE
n_call_b: call BEYOND
n_jcc_s:  cmp eax, eax
          je near STRADDLE
          jmp fail_fallthrough
n_jcc_b:  cmp eax, eax
          je near BEYOND
          jmp fail_fallthrough
n_jmpr:   jmp eax
n_callr:  call eax
n_jmpm:   jmp dword [nearptr]
n_ret:    push eax
          ret

fail_fallthrough:
    jmp SEL_CODE0:fail_ft0
fail_ft0:
    mov ebx, 0xF0
    jmp fail

; After a case: exactly one #GP(0); the target did not execute; for a
; straddling target the frame names it.
check:
    mov ebx, [case_id]
    shl ebx, 8
    inc ebx
    cmp dword [got], 1
    jne fail
    inc ebx
    cmp dword [ebx_seen], 0
    jne fail
    inc ebx
    cmp dword [target], STRADDLE
    jne .done
    cmp dword [got_eip], STRADDLE
    jne fail
    inc ebx
    cmp dword [got_cs], SEL_LIM
    jne fail
.done:
    ret

fail:
    mov eax, ebx
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

isr_gp:
    mov [ss:ebx_seen], ebx
    pop dword [ss:got_ec]
    mov eax, [esp]
    mov [ss:got_eip], eax
    mov eax, [esp + 4]
    mov [ss:got_cs], eax
    inc dword [ss:got]
    mov eax, [ss:resume]
    mov [esp], eax
    mov dword [esp + 4], SEL_CODE0
    iretd

isr_other:
    mov ebx, [ss:case_id]
    shl ebx, 8
    or ebx, 0xEF
    jmp SEL_CODE0:fail

;==================================================================
align 4
case_id:  dd 0
target:   dd 0
resume:   dd 0
got:      dd 0
got_ec:   dd 0
got_eip:  dd 0
got_cs:   dd 0
ebx_seen: dd 0
nearptr:  dd 0
farptr:   dd 0
          dw 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code0, 4 GB
    dq 0x00CF93010000FFFF       ; 0x10 data0, 4 GB
    dq 0x00409B0100001FF7       ; 0x18 code0, limit 1FF7h
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
    IGATE STRADDLE, SEL_LIM     ; 3 (INT3)
%rep 2
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE BEYOND, SEL_LIM       ; 6 (#UD)
%rep 6
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE isr_gp, SEL_CODE0     ; 13
%rep 0x40 - 14
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE STRADDLE, SEL_LIM     ; 40h
    IGATE BEYOND, SEL_LIM       ; 41h
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

; The targets.  Through selector 08h they run and return (the cache fill);
; through selector 18h they must never run.
    times STRADDLE - ($ - $$) db 0xCC
    mov ebx, 0xBAD
    ret
    times BEYOND - ($ - $$) db 0xCC
    mov ebx, 0xBAD
    ret
