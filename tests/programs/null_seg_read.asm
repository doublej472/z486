; null_seg_read.asm - A read through a null data segment raises #GP(0)
;
; Loading a null selector into DS/ES/FS/GS is allowed in protected mode; any
; memory access through it faults. z486 checked only writes (a null loads
; type 0, not writable), so a read went through (Win95 co-simulation:
; cmp word es:[56h], imm with ES = 0 in 16-bit ring-3 code).

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE32 equ 0x08
SEL_DATA32 equ 0x10

start:
    cli
    cld
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    db 0x66, 0xEA
    dd pm32_entry
    dw SEL_CODE32

BITS 32
pm32_entry:
    mov ax, SEL_DATA32
    mov ds, ax
    mov ss, ax
    mov esp, 0x9000
    mov dword [gp_count], 0

    ; ---- 1. word compare through a null ES ----
    xor ax, ax
    mov es, ax
    cmp word [es:0x56], 0x5148          ; #GP(0) -> gp_handler skips it
after1:
    cmp dword [gp_count], 1
    mov eax, 0x10
    jne fail

    ; ---- 2. dword load through a null FS ----
    xor ax, ax
    mov fs, ax
    mov ebx, 0x12345678
    mov ebx, [fs:0x100]                 ; #GP(0)
after2:
    cmp dword [gp_count], 2
    mov eax, 0x20
    jne fail
    cmp ebx, 0x12345678                 ; the load did not happen
    mov eax, 0x21
    jne fail

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

gp_handler:
    ; Frame: error code, EIP, CS, EFLAGS. Error code must be 0.
    cmp dword [esp], 0
    jne .bad_code
    inc dword [gp_count]
    ; Resume after the faulting instruction.
    cmp dword [gp_count], 1
    jne .second
    mov dword [esp + 4], after1
    jmp .done
.second:
    mov dword [esp + 4], after2
.done:
    add esp, 4                          ; drop the error code
    iretd
.bad_code:
    mov eax, [esp]
    or eax, 0x80000000
    jmp fail

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 4
gp_count: dd 0

BITS 16
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF               ; 0x08 code32, base 0x10000
    dq 0x00CF93010000FFFF               ; 0x10 data32, base 0x10000
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times 13 dq 0
    ; #GP: 32-bit interrupt gate
    dw gp_handler
    dw SEL_CODE32
    db 0
    db 10001110b
    dw 0
    times (256 - 13 - 1) dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000
