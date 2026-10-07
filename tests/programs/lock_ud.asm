; lock_ud - LOCK on a non-lockable instruction or a register
; destination raises #UD on a 486
BITS 32
ORG 0
GDT equ 0xA800
IDT equ 0xB000
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff
    mov dword [GDT+12], 0x00cf9b01
    mov dword [GDT+16], 0x0000ffff
    mov dword [GDT+20], 0x00cf9300
    mov word [0xA000], 23
    mov dword [0xA002], GDT
    lgdt [0xA000]
    mov eax, ud_handler
    mov word [IDT+6*8+0], ax
    mov word [IDT+6*8+2], 0x08
    mov word [IDT+6*8+4], 0x8e00
    shr eax, 16
    mov word [IDT+6*8+6], ax
    mov word [0xA010], 0x7ff
    mov dword [0xA012], IDT
    lidt [0xA010]
    xor ebp, ebp
    mov edi, c1
    db 0xf0
    mov eax, [0x9000]            ; lock mov r32, m32
c1: mov edi, c2
    db 0xf0
    add eax, ebx                 ; lock add r32, r32 (register destination)
c2: mov edi, c3
    db 0xf0
    nop
c3: mov edi, c4
    db 0xf0
    cmp dword [0x9000], 1        ; CMP does not write
c4: cmp ebp, 4
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
ud_handler:
    inc ebp
    mov [esp], edi
    iretd
fail:
    mov eax, ebp
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
