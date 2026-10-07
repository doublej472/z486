; pe_cpl0.asm - After CR0.PE is set from real mode with no CS reload, the CPU is
; still the real-mode privilege level (entry CPL0) until CS is reloaded, so
; CPL0-only instructions must execute rather than #GP.
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
start:
    cli
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0x8000

    mov eax, cr0
    mov [saved_cr0], eax
    or  eax, 1
    mov cr0, eax

    ; CPL0-only: CR3 write/read, then a GDT load (a CPL0 instruction that also
    ; exercises the descriptor-table path).
    mov eax, cr3
    mov [saved_cr3], eax
    mov cr3, eax
    mov eax, cr3
    cmp eax, [saved_cr3]
    jne fail1

    lgdt [gdtr]
    mov eax, cr3
    cmp eax, [saved_cr3]
    jne fail2

    mov eax, cr0
    and eax, ~1
    mov cr0, eax

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail1: mov eax, 1
       jmp fail
fail2: mov eax, 2
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang
saved_cr0: dd 0
saved_cr3: dd 0
gdtr: dw 0
      dd 0
