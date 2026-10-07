; seg_stack_wrap_rm.asm - real-mode 16-bit stack at the 64K boundary:
; pop ax at SP=0xFFFE is inside the segment (word 0xFFFE..0xFFFF) and must not
; fault, wrapping SP to 0; popad at SP=0xFFFE crosses the limit and must #SS.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    cli
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov ss, ax

    ; IVT[12]=#SS, IVT[13]=#GP -> fault_handler (same handler, per-case resume).
    xor ax, ax
    mov es, ax
    mov word [es:12*4], fault_handler
    mov word [es:12*4+2], cs
    mov word [es:13*4], fault_handler
    mov word [es:13*4+2], cs

;--- case 1: pop ax at SP=0xFFFE must NOT fault; SP wraps to 0
    mov word [faulted], 0
    mov word [resume_ip], .case1_resume
    mov sp, 0xFFFE
    pop ax
.case1_resume:
    cmp word [faulted], 0
    jne .fail
    cmp sp, 0
    jne .fail

;--- case 2: popad at SP=0xFFFE must #SS (dword crosses the 64K limit)
    mov word [faulted], 0
    mov word [resume_ip], .case2_resume
    mov sp, 0xFFFE
    popad
.case2_resume:
    cmp word [faulted], 1
    jne .fail

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

; #SS/#GP handler: record the fault, restore a sane SP, and jump to the resume
; point the faulting case set up.
fault_handler:
    inc word [cs:faulted]
    mov sp, 0x8000
    mov bx, [cs:resume_ip]
    jmp bx

faulted:  dw 0
resume_ip: dw 0
