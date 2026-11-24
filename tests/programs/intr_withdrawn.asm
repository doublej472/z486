; intr_withdrawn.asm - INTR withdrawn before an instruction boundary is not
; acknowledged.
;
; Intel486 DX Microprocessor data sheet (Oct 1992), 6.4.1 "Interrupt Logic":
; "The INTR Signal is level sensitive and must remain active for the
; instruction execution unit to recognize it: The interrupt will not be
; serviced by the Intel486 Microprocessor if the INTR signal does not remain
; active." and "The instruction execution unit will look at the state of the
; synchronized interrupt signal at specific clocks during the execution of
; instructions (if interrupts are enabled). These specific clocks are at
; instruction boundaries". Section 6.2.8, INTR: "INTR must remain active until
; the interrupt acknowledges have been performed to assure program
; interruption." So a request whose INTR is low at every boundary where IF=1
; and no interrupt shadow is active runs no INTA pair and enters no handler.
;
; Case 1: INTR high only while IF=0, low again before STI.
; Case 2: INTR high across an STI;CLI pair (the STI shadow covers the one
;         boundary with IF=1), low again before a later STI.
; Case 3: IF=1, a short INTR pulse inside one long instruction (ENTER with
;         nesting level 31), low long before its boundary.
; Case 4: control - INTR held until acknowledged, IF=1: taken exactly once.
;
; The INTR pulse port 0xDC: bits 31:16 delay, bits 15:0 width (platform
; cycles); INTR also falls at the second INTA.

BITS 16
org 0

STATUS_PORT        equ 0xE0
DATA_PORT          equ 0xE4
SIGNAL_VECTOR_PORT equ 0xF4
INTR_PULSE_PORT    equ 0xDC

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

INTR_VECTOR equ 0x20

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    xor ax, ax
    mov es, ax
    mov word [es:INTR_VECTOR*4], isr_intr
    mov word [es:INTR_VECTOR*4+2], 0x1000
    mov word [intr_count], 0

    mov dx, SIGNAL_VECTOR_PORT
    mov al, INTR_VECTOR
    out dx, al

    ; ---- case 1: INTR high for 3 cycles while IF=0 -------------------------
    mov dx, INTR_PULSE_PORT
    mov eax, 0x00000003
    out dx, eax
    mov cx, 200
.c1_wait:
    loop .c1_wait
    sti
    times 20 nop
    cli
    cmp word [intr_count], 0
    mov eax, 0x00000001
    jne fail

    ; ---- case 2: a request latched in the STI shadow, withdrawn while IF=0 --
    mov dx, INTR_PULSE_PORT
    mov eax, 2000           ; INTR high now, for 2000 platform cycles
    out dx, eax
    times 10 nop            ; let INTR reach the CPU (IF=0)
    sti                     ; IF=1 with INTR high, but the next boundary is
    cli                     ; in the STI shadow, and after CLI IF=0
    cmp word [intr_count], 0
    mov eax, 0x00000002
    jne fail
    mov cx, 4000            ; INTR goes low in here (IF=0 throughout)
.c2_wait:
    loop .c2_wait
    sti                     ; every boundary from here on sees INTR low
    times 20 nop
    cli
    cmp word [intr_count], 0
    mov eax, 0x00000003
    jne fail

    ; ---- case 3: a 4-cycle INTR pulse inside ENTER imm16, 31 ---------------
    mov bp, sp
    mov dx, INTR_PULSE_PORT
    mov eax, 0x00140004     ; after 20 cycles, high for 4
    sti
    out dx, eax
    enter 0, 31             ; 30 frame-pointer copies: one long instruction
    leave
    times 20 nop
    cli
    cmp word [intr_count], 0
    mov eax, 0x00000004
    jne fail

    ; ---- case 4: control - INTR held until the acknowledge -----------------
    mov dx, INTR_PULSE_PORT
    mov eax, 0x0000FFFF
    out dx, eax
    sti
    times 40 nop
    cli
    cmp word [intr_count], 1
    mov eax, 0x00000005
    jne fail

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

isr_intr:
    inc word [cs:intr_count]
    iret

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 2
intr_count: dw 0
