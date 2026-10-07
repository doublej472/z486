; far_jump_pm.asm - protected-mode memory-indirect far transfers:
; jmp far [mem] (FF /5) and call far [mem] (FF /3) through a 6-byte
; (offset32, selector16) pointer, plus retf.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE32  equ 0x08
SEL_DATA32  equ 0x10

start:
    cli
    lgdt [cs:gdt_desc]

    ; Enter protected mode
    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    db 0x66, 0xEA           ; jmp far ptr16:32 to load CS from the GDT
    dd pm32_entry
    dw SEL_CODE32

BITS 32
pm32_entry:
    mov ax, SEL_DATA32
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x2000

    ; --- TEST 1: memory-indirect far jump (FF /5) --------------------------
    mov dword [fptr+0], t1_target
    mov word  [fptr+4], SEL_CODE32
    jmp far [fptr]          ; CS:EIP <- [fptr] (offset32, selector16)
t1_dead:
    mov al, 0xEE
    jmp fail
t1_target:
    mov dl, 0x01            ; landed via jmp m16:32

    ; --- TEST 2: memory-indirect far call (FF /3) + retf -------------------
    mov dword [fptr+0], t2_sub
    mov word  [fptr+4], SEL_CODE32
    call far [fptr]         ; pushes CS:EIP, then loads [fptr]
    cmp dl, 0x02            ; retf returned here
    jne fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

t2_sub:
    mov dl, 0x02
    retf

fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
gdt:
    dq 0x0000000000000000                          ; 0x00: NULL
    dq 0x00CF9B010000FFFF                          ; 0x08: 32-bit code, base=0x10000
    dq 0x00CF93010000FFFF                          ; 0x10: 32-bit data, base=0x10000
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000     ; GDT base (image loaded at phys 0x10000)

fptr: dd 0, 0               ; 6-byte far pointer (offset32 + selector16), padded
