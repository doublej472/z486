; cs_limit_fetch_errcode.asm - a #GP raised by a fetch beyond the CS limit pushes error code 0
;
; i486 Programmer's Reference Manual (1992), 9.9.13 Interrupt 13 - General
; Protection, p. 9-20: a general-protection exception is caused by
; "Exceeding the segment limit when using the CS, DS, ES, FS, or GS
; segments"; p. 9-21: "If loading a descriptor causes the exception, the
; error code contains a selector to the descriptor; otherwise, the error code
; is null."  A code fetch beyond the limit loads no descriptor: 0.
;
; Each case reaches the limit of selector 18h (code32, base 10000h, limit
; 1FF7h) with the microcode idle, so the fetch-side #GP is the only event:
;
;   1  sequential: NOPs at 1FF0h-1FF7h run, the fetch at 1FF8h faults
;   2  a 5-byte MOV EBX,0BADh at 0FF5h straddles the limit of selector 28h
;      (code32, base 10000h, limit 0FF7h)
;   3  as 1, entered with a far JMP whose selector (18h) the microcode
;      leaves in its scratch registers
;   4  as 1 in selector 20h, a 16-bit code segment (limit 1FF7h)
;
; The handler checks the error code's low word: the error-code push writes
; two bytes into a 32-bit slot (microsequencer.sv, uc_force_word), so the
; upper half is not this test's question.  It also checks the frame CS:EIP (the first byte
; beyond the limit, or the straddling instruction) and that EBX stayed 0.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4:
; (case << 8) | check.  Checks: 1 exactly one #GP, 2 error code, 3 frame
; EIP, 4 frame CS, 5 EBX.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08    ; code32, base 10000h, 4 GB
SEL_DATA0   equ 0x10    ; data32, base 10000h, 4 GB
SEL_LIM     equ 0x18    ; code32, base 10000h, limit 1FF7h
SEL_LIM16   equ 0x20    ; code16, base 10000h, limit 1FF7h
SEL_LIM2    equ 0x28    ; code32, base 10000h, limit 0FF7h

RUNIN       equ 0x1FF0  ; NOPs to the limit
STRADDLE    equ 0x0FF5  ; MOV EBX,0BADh at 0FF5h-0FF9h (selector 28h)
BEYOND1     equ 0x1FF8  ; first offset beyond the limit
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

; %1 case, %2 expected frame EIP, %3 expected frame CS, then the entry.
%macro CASE 3
    mov dword [case_id], %1
    mov dword [exp_eip], %2
    mov dword [exp_cs], %3
    mov dword [resume], %%next
    mov dword [got], 0
    mov dword [got_ec], 0xEEEEEEEE
    mov dword [got_eip], 0xEEEEEEEE
    mov dword [got_cs], 0xEEEEEEEE
    mov dword [ebx_seen], 0xEEEEEEEE
    mov esp, STACK_TOP
    xor ebx, ebx
%define CNEXT %%next
%endmacro
%macro CEND 0
CNEXT:
    call check
%undef CNEXT
%endmacro

    ; 1: enter selector 18h at a stub well inside the limit (the far JMP's
    ; own microcode finishes long before the fetch reaches the limit).
    CASE 1, BEYOND1, SEL_LIM
    jmp SEL_LIM:stub_runin
    CEND

    ; 2: the straddling instruction, reached sequentially.
    CASE 2, STRADDLE, SEL_LIM2
    jmp SEL_LIM2:stub_straddle
    CEND

    ; 3: far JMP straight to the run-in NOPs.
    CASE 3, BEYOND1, SEL_LIM
    jmp SEL_LIM:RUNIN
    CEND

    ; 4: the 16-bit code segment.
    CASE 4, BEYOND1, SEL_LIM16
    jmp SEL_LIM16:stub_runin16
    CEND

    mov al, 0x01
    out STATUS_PORT, al
    hlt

stub_runin:
    mov ecx, 64
.spin:
    dec ecx
    jnz .spin
    jmp RUNIN
stub_straddle:
    mov ecx, 64
.spin:
    dec ecx
    jnz .spin
    jmp STRADDLE
BITS 16
stub_runin16:
    mov cx, 64
.spin:
    dec cx
    jnz .spin
    jmp RUNIN
BITS 32

check:
    mov edx, [case_id]
    shl edx, 8
    inc edx
    cmp dword [got], 1
    jne fail
    inc edx
    cmp word [got_ec], 0
    jne fail
    inc edx
    mov eax, [exp_eip]
    cmp [got_eip], eax
    jne fail
    inc edx
    mov eax, [exp_cs]
    cmp [got_cs], eax
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
    shl edx, 8
    or edx, 0xEF
    jmp SEL_CODE0:fail

;==================================================================
align 4
case_id:  dd 0
exp_eip:  dd 0
exp_cs:   dd 0
resume:   dd 0
got:      dd 0
got_ec:   dd 0
got_eip:  dd 0
got_cs:   dd 0
ebx_seen: dd 0

align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF       ; 0x08 code32, 4 GB
    dq 0x00CF93010000FFFF       ; 0x10 data32, 4 GB
    dq 0x00409B0100001FF7       ; 0x18 code32, limit 1FF7h
    dq 0x00009B0100001FF7       ; 0x20 code16, limit 1FF7h
    dq 0x00409B0100000FF7       ; 0x28 code32, limit 0FF7h
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
%rep 13
    IGATE isr_other, SEL_CODE0
%endrep
    IGATE isr_gp, SEL_CODE0     ; 13
%rep 32 - 14
    IGATE isr_other, SEL_CODE0
%endrep
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

    times STRADDLE - ($ - $$) db 0xCC
    mov ebx, 0xBAD              ; 0FF5h-0FF9h: crosses selector 28h's limit
    times RUNIN - ($ - $$) db 0xCC
    times BEYOND1 - RUNIN db 0x90
    mov ebx, 0xBAD              ; 1FF8h: beyond selector 18h's / 20h's limit
    times 0x2010 - ($ - $$) db 0xCC
