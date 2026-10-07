; pc98_a20_bit20.asm - the PC-98 preset's A20 mask clears physical bit 20 only
;
; The PC-9821's A20 gate drives the 486's A20M#, which clears address bit 20 and
; nothing else (measured on the owner's Xe10 with tools/hwprobe A20MAP in the
; PC-9821 core repo: with A20 masked, X+1M aliases X and X+3M aliases X+2M,
; while X+2M and X+16M keep their own cells). A 1 MiB wrap (every bit above 19
; cleared) is what NP2kai models, and what this preset used to do; it sends a
; masked access to 0x205000 to 0x005000 instead.
;
; The bench's memory wraps at its own size, so the check is on the BUS address:
; it counts memory writes with bit 21 set (IN 0xD0) and writes with bit 20 set
; while A20 was masked (IN 0xD4). The bench's A20 input is OUT 0xF0 (mask) /
; OUT 0xF4 (unmask).

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    mov esp, 0x0003F000

    in eax, 0xD0
    mov esi, eax                    ; bit-21 writes so far
    in eax, 0xD4
    mov edi, eax                    ; masked bit-20 writes so far

    out 0xF0, al                    ; A20 masked
    mov dword [0x00205000], 0x20520520   ; bit 21 must survive the mask
    mov dword [0x00105000], 0x10510510   ; bit 20 must not
    out 0xF4, al                    ; A20 open again

    in eax, 0xD0
    sub eax, esi
    cmp eax, 1
    jne .fail_1
    in eax, 0xD4
    sub eax, edi
    jnz .fail_2

    mov al, 0x01
    out STATUS_PORT, al
    hlt

.fail_1:
    mov ebx, 1
    jmp .fail
.fail_2:
    mov ebx, 2
.fail:
    out DATA_PORT, eax
    mov eax, ebx
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
