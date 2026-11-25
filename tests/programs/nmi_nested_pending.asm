; nmi_nested_pending.asm - an NMI edge during the NMI handler is held to IRET
;
; Intel486 DX data sheet (Oct 1992) 2.7.4 Non-Maskable Interrupt, p. 46:
; "While executing the NMI servicing procedure, the Intel486 Microprocessor
; will not service further NMI requests until an interrupt return (IRET)
; instruction is executed or the processor is reset. If NMI occurs while
; currently servicing an NMI, its presence will be saved for servicing after
; executing the first IRET instruction."  (Same text: Embedded Intel486
; Processor Family Developer's Manual 3.15.4.)
;
; The first handler raises a second NMI edge (the bench's signal port, after
; the first pulse has ended), spins, and returns with IRET. Expected: the
; second NMI is not taken inside the first handler, and is taken exactly once
; after its IRET. Port 0xE4 on failure: 1 = no second NMI, 2 = nested entry
; (a return IP inside the handler), 3 = wrong count.

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

start:
    jmp near main

align 2
nmi_count:  dw 0
nested:     dw 0

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
    mov dx, SIGNAL_CYCLES_PORT
    mov ax, 1
    out dx, ax
    mov dx, SIGNAL_NMIWIDTH_PORT
    mov ax, 4
    out dx, ax

    mov dx, SIGNAL_PORT
    mov al, 2               ; first NMI
    out dx, al

    mov cx, 3000
.wait:
    cmp word [nmi_count], 2
    jae .got
    dec cx
    jnz .wait
    mov eax, 0x00000001     ; second NMI never taken
    jmp near fail
.got:
    mov cx, 200
.settle:
    dec cx
    jnz .settle
    cmp word [nested], 0
    je .not_nested
    mov eax, 0x00000002
    jmp near fail
.not_nested:
    cmp word [nmi_count], 2
    je .pass
    mov eax, 0x00000003
    jmp near fail
.pass:
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

isr_nmi:
    push bp
    mov bp, sp
    push ax
    push cx
    push dx
    ; An entry whose return IP lies inside this handler interrupted it.
    mov ax, [bp+2]
    cmp ax, isr_nmi
    jb .not_inside
    cmp ax, isr_end
    jae .not_inside
    mov word [cs:nested], 1
.not_inside:
    inc word [cs:nmi_count]
    cmp word [cs:nmi_count], 1
    jne .out
    ; Let the first pulse (4 clocks) end, then request a second edge.
    mov cx, 8
.low:
    dec cx
    jnz .low
    mov dx, SIGNAL_PORT
    mov al, 2
    out dx, al
    mov cx, 300             ; the second edge arrives while this spins
.spin:
    dec cx
    jnz .spin
.out:
    pop dx
    pop cx
    pop ax
    pop bp
    iret
isr_end:

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $
