; x87_off_sx.asm - Dev-menu x87 Off behaves like a 486SX (run with +z486_x87_off)
;
; With no FPU, an ESC instruction that passes its CR0 checks does nothing:
; FNSTSW/FNSTCW leave their destination as it was (the 5A5Ah detection idiom
; then reports no FPU), FSTP writes no memory, and WAIT completes. CR0.EM=1
; still raises #NM, so an emulator can take over.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    jmp main
    times 0x80-($-$$) db 0      ; keep the IVT entries we write clear of code

main:
    cli
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x700

    ; #NM (vector 7) -> nm_handler
    push ds
    xor ax, ax
    mov ds, ax
    mov word [7*4], nm_handler
    mov [7*4+2], cs
    pop ds

    mov word [sw], 0x5A5A
    fninit
    fnstsw word [sw]
    cmp word [sw], 0x5A5A
    jne fail1

    mov ax, 0x5A5A
    fnstsw ax
    cmp ax, 0x5A5A
    jne fail2

    mov word [cw], 0x5A5A
    fnstcw word [cw]
    cmp word [cw], 0x5A5A
    jne fail3

    mov dword [out], 0x12345678
    fld dword [val]
    fstp dword [out]
    cmp dword [out], 0x12345678
    jne fail4

    wait

    ; CR0.EM=1: FNINIT faults with #NM; the handler clears EM and returns to
    ; the FNINIT, which then completes as a no-op.
    mov byte [nm_count], 0
    mov eax, cr0
    or al, 4
    mov cr0, eax
    fninit
    cmp byte [nm_count], 1
    jne fail5

    mov al, 0x01
    out STATUS_PORT, al
    hlt

nm_handler:
    inc byte [cs:nm_count]
    push eax
    mov eax, cr0
    and al, 0xFB
    mov cr0, eax
    pop eax
    iret

fail1: mov eax, 1
    jmp fail
fail2: movzx eax, ax
    or eax, 0x20000
    jmp fail
fail3: mov eax, 3
    jmp fail
fail4: mov eax, 4
    jmp fail
fail5: movzx eax, byte [nm_count]
    or eax, 0x50000
fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

align 4
val:      dd 0x3F800000
out:      dd 0
sw:       dw 0
cw:       dw 0
nm_count: db 0
