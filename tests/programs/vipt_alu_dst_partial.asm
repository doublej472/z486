; A VIPT ALU result (e.g. `and eax,[mem]`) is not forwarded; a younger partial
; write (`mov al,[mem]`) merges the destination's upper bytes and must see the
; ALU result, not the pre-ALU EAX.
BITS 32
ORG 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
V1 equ 0x00040000
V2 equ 0x00040010
start:
    cli
    mov esp, 0x0003F000
    mov dword [V1], 0x00FF00FF
    mov dword [V2], 0x000000AA
    mov eax, 0xFFFFFFFF
    mov ecx, V1
    mov edx, V2
    and eax, [ecx]        ; VIPT ALU, result 0x00FF00FF (not forwarded)
    mov al, [edx]         ; partial write: upper 24 bits from EAX
    cmp eax, 0x00FF00AA
    jne fail
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xff
    mov dx, STATUS_PORT
    out dx, al
    hlt
