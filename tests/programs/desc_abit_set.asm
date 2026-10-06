; desc_abit_set - loading a segment register from a code/data descriptor with
; A=0 sets the descriptor's Accessed bit in the GDT (Intel486 PRM 5.1.1/6.3)
;
; DS (0x10), SS (0x18), ES (0x20, read-only data) and CS (0x28, via far JMP)
; are loaded from descriptors whose A bit is clear; afterwards each access byte
; must read back with A set (92h->93h, 90h->91h, 9Ah->9Bh).  Fail: port 0xE4 =
; selector << 16 | access byte read back.
BITS 32
ORG 0
GDT equ 0x9800
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff        ; 0x08: code, base 0x10000 (current CS)
    mov dword [GDT+12], 0x00cf9b01
    mov dword [GDT+16], 0x0000ffff       ; 0x10: flat data, A=0
    mov dword [GDT+20], 0x00cf9200
    mov dword [GDT+24], 0x0000ffff       ; 0x18: flat data (stack), A=0
    mov dword [GDT+28], 0x00cf9200
    mov dword [GDT+32], 0x0000ffff       ; 0x20: flat read-only data, A=0
    mov dword [GDT+36], 0x00cf9000
    mov dword [GDT+40], 0x0000ffff       ; 0x28: code, base 0x10000, A=0
    mov dword [GDT+44], 0x00cf9a01
    mov word [0x9700], 47
    mov dword [0x9702], GDT
    lgdt [0x9700]
    mov ax, 0x10
    mov ds, ax
    mov ax, 0x18
    mov ss, ax
    mov ax, 0x20
    mov es, ax
    jmp 0x28:.cs
.cs:
    mov ebx, 0x10
    mov cl, 0x93
    call check
    mov ebx, 0x18
    mov cl, 0x93
    call check
    mov ebx, 0x20
    mov cl, 0x91
    call check
    mov ebx, 0x28
    mov cl, 0x9b
    call check
    mov al, 1
    out 0xe0, al
    hlt
check:
    movzx eax, byte [GDT+ebx+5]
    cmp al, cl
    jne fail
    ret
fail:
    shl ebx, 16
    or eax, ebx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
