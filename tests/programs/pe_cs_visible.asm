; pe_cs_visible.asm - Setting CR0.PE from real mode must keep CS's *visible*
; selector and its cached real-mode base, until a far transfer reloads CS.
; HIMEM-style code toggles PE and then keeps addressing through CS, so a base
; that changed to 0 (or a descriptor reload) corrupts memory silently.
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
MARKER equ 0x0180
start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000
    mov [saved_cs], ax

    ; Marker written in plain real mode, addressed through CS later.
    mov word [MARKER], 0xBEEF

    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    ; Visible selector unchanged.
    mov bx, cs
    cmp bx, [saved_cs]
    jne fail1

    ; CS's cached base unchanged: the same physical word is still visible.
    mov ax, [cs:MARKER]
    cmp ax, 0xBEEF
    jne fail2

    ; And through DS, whose cached base must also have survived.
    mov ax, [ds:MARKER]
    cmp ax, 0xBEEF
    jne fail3

    mov eax, cr0
    and eax, ~1
    mov cr0, eax

    mov bx, cs
    cmp bx, [saved_cs]
    jne fail4
    mov ax, [cs:MARKER]
    cmp ax, 0xBEEF
    jne fail5

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail1: mov eax, 1
       jmp fail
fail2: mov eax, 2
       jmp fail
fail3: mov eax, 3
       jmp fail
fail4: mov eax, 4
       jmp fail
fail5: mov eax, 5
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang
saved_cs: dw 0
