; ts_286_min_limit - a task switch to a 286 TSS whose limit is exactly 2Bh
; (its minimum) succeeds
;
; Intel486 PRM: #TS(new TSS) if the new TSS limit is below 67h for a 386 TSS
; or 2Bh for a 286 TSS.  JMP to an available 286 TSS (type 1, limit 2Bh) must
; load the 286 task state (AX/BX/SP/segments) and run it; requiring 67h for a
; 286 TSS too raises #TS instead (the test then shuts down / times out).
; (derived from task_switch_jmp386)
; task_switch_jmp386.asm - far JMP to an available 386 TSS
;
; The LOAD_TASK microcode selects DES_TR with IN=2 before walking the new
; TSS.  Losing that segment selection reads offsets from linear address zero
; instead of TR.base + offset and corrupts the entire incoming task state.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE    equ 0x2B             ; GDT code, RPL 3
SEL_DATA    equ 0x33             ; GDT data, RPL 3
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_NEW equ 0x20

STACK_OLD   equ 0x3000
STACK_NEW   equ 0x4000

start:
    cli
    lgdt [cs:gdt_desc]

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
    mov esp, STACK_OLD

    mov ax, SEL_TSS_OLD
    ltr ax

    ; A task-switch JMP ignores the pointer offset and loads EIP from tss_new.
    jmp SEL_TSS_NEW:0

    mov eax, 0x10
    jmp fail

task_entry:
    cmp ax, 0x3344
    jne fail_21
    cmp bx, 0x7788
    jne fail_22
    cmp sp, STACK_NEW
    jne fail_23
    mov ax, cs
    cmp ax, SEL_CODE
    jne fail_24
    mov ax, ss
    cmp ax, SEL_DATA
    jne fail_25

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_21:
    mov eax, 0x21
    jmp fail
fail_22:
    mov eax, 0x22
    jmp fail
fail_23:
    mov eax, 0x23
    jmp fail
fail_24:
    mov eax, 0x24
    jmp fail
fail_25:
    mov eax, 0x25
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08: 32-bit code, base 10000h
    dq 0x00CF93010000FFFF       ; 10: 32-bit data, base 10000h

    ; 18: available 386 TSS, base 10000h + tss_old, limit 67h
    dw 0x0067
    dw tss_old
    db 0x01
    db 10001001b
    db 0
    db 0

    ; 20: available 386 TSS, base 10000h + tss_new, limit 67h
    dw 0x002B                   ; 286 TSS minimum limit
    dw tss_new
    db 0x01
    db 10000001b                ; available 286 TSS
    db 0
    db 0

    dq 0x00CFFB010000FFFF       ; 28: 32-bit ring-3 code, base 10000h
    dq 0x00CFF3010000FFFF       ; 30: 32-bit ring-3 data, base 10000h
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 4
tss_old:
    times 26 dd 0

align 4
tss_new:                        ; 286 TSS (44 bytes)
    dw 0                        ; 00 backlink
    dw 0, 0                     ; 02 SP0, SS0
    dw 0, 0                     ; 06 SP1, SS1
    dw 0, 0                     ; 0A SP2, SS2
    dw task_entry               ; 0E IP
    dw 0x3002                   ; 10 FLAGS (IOPL=3)
    dw 0x3344                   ; 12 AX
    dw 0                        ; 14 CX
    dw 0                        ; 16 DX
    dw 0x7788                   ; 18 BX
    dw STACK_NEW                ; 1A SP
    dw 0                        ; 1C BP
    dw 0                        ; 1E SI
    dw 0                        ; 20 DI
    dw SEL_DATA                 ; 22 ES
    dw SEL_CODE                 ; 24 CS
    dw SEL_DATA                 ; 26 SS
    dw SEL_DATA                 ; 28 DS
    dw 0                        ; 2A LDT
