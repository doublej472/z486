; unreal_cs_cpl - after MOV CR0 sets PE the visible CS is preserved (including
; its low two bits) and CPL stays 0 until the first CS reload.  With the real
; mode CS left at 1001h, a DPL0 descriptor load must still succeed, and
; `push cs` must still report 1001h.
BITS 16
cpu 386
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    cld
    xor ax, ax
    mov ss, ax
    mov sp, 9000h
    mov ax, cs
    mov ds, ax                 ; DS base = CS base (real mode)
    lgdt [cs:gdtr]

    ; ---- control: CS = 1000h (low bits 00) -> CPL 0 naturally
    mov word [entry+2], 1000h
    mov word [entry], bounce - 0
    call far [entry]

    ; ---- case: CS = 1001h (low bits 01) -> still CPL 0 until CS reload
    mov word [entry+2], 1001h
    mov word [entry], bounce - 10h
    call far [entry]

    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

; ---- reached with CS = 0x1000 or 0x1001; returns via retf in real mode ----
bounce:
    push cs
    pop bx
    mov word [seen_cs], bx
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp short .in_pm
.in_pm:
    push cs
    pop bx
    cmp bx, [seen_cs]          ; visible CS preserved across PE
    jne fail
    ; A DPL0 data descriptor load needs CPL 0.  At CPL 1 (the bug) this #GP.
    mov dx, 10h
    mov ds, dx
    mov es, dx
    ; back to real mode and return to the caller
    mov eax, cr0
    and al, 0feh
    mov cr0, eax
    jmp 1000h:.rm
.rm:
    retf

fail:
    mov al, 0xff
    mov dx, STATUS_PORT
    out dx, al
    hlt

entry: dd 0
seen_cs: dw 0

align 8
gdt:
    dq 0
    dq 00009a000000ffffh       ; 08: code, DPL0, base 0
    dq 00cf92000000ffffh       ; 10: data, DPL0, base 0
gdtr:
    dw 23
    dd gdt + 0x10000
