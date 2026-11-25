; nmi_ss_shadow.asm - NMI is held through the MOV SS / POP SS shadow
;
; Intel486 PRM (1992) 9.3.4 "MOV or POP to SS Masks Some Exceptions and
; Interrupts", p. 9-5: "the Intel486 processor inhibits interrupts, debug
; exceptions, and single-step trap exceptions after either a MOV to SS
; instruction or a POP to SS instruction, until the instruction boundary
; following the next instruction is reached."  POP instruction, p. 26-231:
; "A POP SS instruction inhibits all interrupts, including NMI, until after
; execution of the next instruction."
;
; Each attempt requests an NMI k clocks after the request OUT (k = 1..MAX_K;
; the bench's retired-instruction trigger does not count a shadowed boundary,
; so it cannot land an edge inside the window), then runs a block of 4-byte groups whose third byte starts
; the instruction that follows an SS load:
;   MOV SS block:  mov ss,ax (8E D0) ; mov sp,bx (89 DC)
;   POP SS block:  push ax   (50)    ; pop ss (17) ; mov sp,bx (89 DC)
; The NMI handler records the return IP. A return IP at group offset 2 means
; the NMI was taken between the SS load and the next instruction: FAIL. Every
; attempt must take exactly one NMI. The STI shadow, which does not hold NMI,
; is covered by nmi_during_sti_shadow.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SIGNAL_PORT equ 0xE8
SIGNAL_CYCLES_PORT equ 0xEC
SIGNAL_INSTR_PORT  equ 0xF0
SIGNAL_NMIWIDTH_PORT equ 0xF8

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

NMI_VECTOR equ 0x02
MAX_K      equ 48
GROUPS     equ 8

start:
    jmp near main

align 2
nmi_count:  dw 0
ret_ip:     dw 0
k:          dw 0, 0

main:
    cli
    cld

    mov ax, cs
    mov ds, ax

    xor ax, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000
    mov word [es:NMI_VECTOR*4], isr_nmi
    mov word [es:NMI_VECTOR*4+2], 0x1000

    mov dx, SIGNAL_INSTR_PORT
    xor ax, ax              ; cycle-delay mode
    out dx, ax
    mov dx, SIGNAL_NMIWIDTH_PORT
    mov ax, 8
    out dx, ax

    ; ---- MOV SS block ----
    mov word [k], 1
movss_attempt:
    mov word [nmi_count], 0
    mov word [ret_ip], 0xFFFF
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, [k]
    out dx, ax
    xor ax, ax              ; SS value (unchanged: the stack stays valid)
    mov bx, sp
    mov dx, SIGNAL_PORT
    mov cl, 2
    xchg al, cl
    out dx, al              ; request NMI k instructions from here
    xchg al, cl             ; al = 0 again (ax = SS value)
movss_block:
%rep GROUPS
    mov ss, ax
    mov sp, bx
%endrep
    nop
    nop
    call wait_one
    mov si, movss_block
    call check_ret
    inc word [k]
    cmp word [k], MAX_K
    jbe movss_attempt

    ; ---- POP SS block ----
    mov word [k], 1
popss_attempt:
    mov word [nmi_count], 0
    mov word [ret_ip], 0xFFFF
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, [k]
    out dx, ax
    xor ax, ax
    mov bx, sp
    mov dx, SIGNAL_PORT
    mov cl, 2
    xchg al, cl
    out dx, al
    xchg al, cl
popss_block:
%rep GROUPS
    push ax
    pop ss
    mov sp, bx
%endrep
    nop
    nop
    call wait_one
    mov si, popss_block
    call check_ret
    inc word [k]
    cmp word [k], MAX_K
    jbe popss_attempt

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

; Wait for the NMI of this attempt; exactly one must arrive.
wait_one:
    mov cx, 2000
.w:
    cmp word [nmi_count], 0
    jne .got
    dec cx
    jnz .w
    mov eax, 0x00000001     ; timeout waiting for NMI
    jmp near fail
.got:
    mov cx, 50
.w2:
    dec cx
    jnz .w2
    cmp word [nmi_count], 1
    je .ok
    mov eax, 0x00000003     ; more than one NMI
    jmp near fail
.ok:
    ret

; SI = block start. Fail if the NMI returned to group offset 2 inside it.
check_ret:
    mov ax, [ret_ip]
    sub ax, si
    jb .ok                  ; before the block
    cmp ax, GROUPS*4
    jae .ok                 ; after the block
    and ax, 3
    cmp ax, 2
    jne .ok
    mov eax, [k]
    shl eax, 16
    mov ax, [ret_ip]
    or eax, 0x80000000      ; 0x8kkk_IIII: NMI inside the SS shadow at IP IIII
    jmp near fail
.ok:
    ret

isr_nmi:
    push bp
    mov bp, sp
    push ax
    mov ax, [bp+2]          ; return IP
    mov [cs:ret_ip], ax
    inc word [cs:nmi_count]
    pop ax
    pop bp
    iret

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

