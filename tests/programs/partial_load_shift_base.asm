; Directed regression: a byte/word load merging into a register whose deferred
; shift write lands on the load's capture edge, then a full-width store of that
; register. Windows 3.11's VMM builds a far callback pointer this way
; (shl ecx,16 / mov cx,[mem] / mov [esi],ecx); the store wrote the merged
; value with the pre-shift upper half (selector zero).
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    mov word [0x1000], 0x043C
    mov byte [0x1004], 0x5A
    mov esi, 0x1100
    ; warm the cache lines
    mov eax, [0x1000]
    mov eax, [0x1100]
    mov eax, [0x1104]
    mov eax, [0x1108]
    ; case 1: word load after shl, then dword store
    mov ecx, 0x000001D7
    shl ecx, 16
    mov cx, [0x1000]
    mov [esi], ecx
    cmp dword [0x1100], 0x01D7043C
    mov ebx, 1
    jne fail
    cmp ecx, 0x01D7043C
    mov ebx, 2
    jne fail
    ; case 2: low-byte load after shl
    mov edx, 0x00000012
    shl edx, 8
    mov dl, [0x1004]
    mov [esi + 4], edx
    cmp dword [0x1104], 0x0000125A
    mov ebx, 3
    jne fail
    ; case 3: high-byte load after shr
    mov eax, 0x12340000
    shr eax, 16
    mov ah, [0x1004]
    mov [esi + 8], eax
    cmp dword [0x1108], 0x00005A34
    mov ebx, 4
    jne fail
    ; case 4: word load after rol, consumed by an ALU op
    mov ecx, 0x0000ABCD
    rol ecx, 16
    mov cx, [0x1000]
    add ecx, 0
    cmp ecx, 0xABCD043C
    mov ebx, 5
    jne fail
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang
fail:
    mov eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
