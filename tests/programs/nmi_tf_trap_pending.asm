; nmi_tf_trap_pending.asm - an NMI that meets a single-step trap is held, not lost
;
; Intel 64 and IA-32 SDM Vol. 3A, 6.9 "Priority Among Simultaneous Exceptions
; and Interrupts", Table 6-2: class 4, "Traps on the Previous Instruction ...
; Debug Trap Exceptions (TF flag set or data/I-O breakpoint)", is above class
; 5, "Nonmaskable Interrupts (NMI)"; and "Lower priority exceptions are
; discarded; lower priority interrupts are held pending."  So when TF's trap
; and an NMI are due at one instruction boundary, #DB is taken first and the
; NMI is still delivered afterwards.
;
; Each trial requests one NMI with a cycle delay of 1..MAX_DELAY, then single-
; steps a run of slow DIVs, so many of the edges land inside a stepped
; instruction and are first seen at a boundary where the TF trap is pending.
; Expected: every requested NMI is taken exactly once.  Port 0xE4 on failure:
; 0x0001_nnnn = only nnnn NMIs for MAX_DELAY trials; 0x0002_nnnn = no #DB
; entries (TF never stepped, nnnn = NMI count).

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

DB_VECTOR  equ 0x01
NMI_VECTOR equ 0x02
MAX_DELAY  equ 96

start:
    jmp near main

align 2
nmi_count:  dw 0
db_count:   dw 0

main:
    cli
    cld

    mov ax, cs
    mov ds, ax

    xor ax, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000
    mov word [es:DB_VECTOR*4], isr_db
    mov word [es:DB_VECTOR*4+2], 0x1000
    mov word [es:NMI_VECTOR*4], isr_nmi
    mov word [es:NMI_VECTOR*4+2], 0x1000

    mov dx, SIGNAL_INSTR_PORT
    xor ax, ax              ; cycle-delay mode
    out dx, ax
    mov dx, SIGNAL_NMIWIDTH_PORT
    mov ax, 4
    out dx, ax

    mov si, 1               ; the trial's cycle delay
.trial:
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, si
    out dx, ax
    mov dx, SIGNAL_PORT
    mov al, 2
    out dx, al

    xor edx, edx
    mov eax, 0x7FFFFFFF
    mov ebx, 3
    pushf
    pop ax
    or ax, 0x0100           ; TF: trap after each following instruction
    push ax
    popf
    div ebx
    div ebx
    div ebx
    div ebx
    div ebx
    div ebx
    pushf
    pop ax
    and ax, 0xFEFF
    push ax
    popf

    mov cx, 200             ; let a still-pending NMI arrive
.settle:
    dec cx
    jnz .settle

    inc si
    cmp si, MAX_DELAY
    jbe .trial

    cmp word [db_count], 0
    jne .stepped
    movzx eax, word [nmi_count]
    or eax, 0x00020000
    jmp near fail
.stepped:
    cmp word [nmi_count], MAX_DELAY
    je .pass
    movzx eax, word [nmi_count]
    or eax, 0x00010000
    jmp near fail
.pass:
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

isr_db:
    inc word [cs:db_count]
    iret

isr_nmi:
    inc word [cs:nmi_count]
    iret

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $
