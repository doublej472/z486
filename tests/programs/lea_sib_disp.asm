; Directed regression: LEA with SIB and displacement issued right after a
; run of MOV r,imm, as test386's generated 32-bit addressing test does, and a
; split (base + index + disp) EA whose index is written by the instruction just
; before it.
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    ; case 1: lea eax, [ecx*4 + 0x80000000]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [ecx*4 + 0x80000000]
    nop
    nop
    nop
    cmp eax, 0x80000010
    mov ebx, 1
    jne fail
    ; case 2: lea eax, [edx*2 + 0x80000000]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [edx*2 + 0x80000000]
    nop
    nop
    nop
    cmp eax, 0x80000010
    mov ebx, 2
    jne fail
    ; case 3: lea eax, [ebx*8 + 0x80000000]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [ebx*8 + 0x80000000]
    nop
    nop
    nop
    cmp eax, 0x80000010
    mov ebx, 3
    jne fail
    ; case 4: lea eax, [esi + 0x80000000]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [esi + 0x80000000]
    nop
    nop
    nop
    cmp eax, 0x80000080
    mov ebx, 4
    jne fail
    ; case 5: lea eax, [ebp + ecx*4 + 0x80]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [ebp + ecx*4 + 0x80]
    nop
    nop
    nop
    cmp eax, 0x000000D0
    mov ebx, 5
    jne fail
    ; case 6: lea eax, [edi + esi*2 + 0x80000000]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [edi + esi*2 + 0x80000000]
    nop
    nop
    nop
    cmp eax, 0x80000200
    mov ebx, 6
    jne fail
    ; case 7: lea eax, [ecx*4]
    mov eax, 0x001
    mov ebx, 0x002
    mov ecx, 0x004
    mov edx, 0x008
    mov ebp, 0x040
    mov esi, 0x080
    mov edi, 0x100
    lea eax, [ecx*4]
    nop
    nop
    nop
    cmp eax, 0x00000010
    mov ebx, 7
    jne fail
    ; case 8: a recipe commit to the index on the split-EA capture edge
    ; (test386's table lookup: and edx, 0xFF / mov edx, [cs:ebp + edx*4]; the
    ; base here is ESI so the default segment is DS)
    mov dword [0x1000], 0x11111111
    mov dword [0x1004], 0x22222222
    mov dword [0x1008], 0x33333333
    mov esi, 0x1000
    mov edx, 0xABCD0002
    and edx, 0xFF
    mov edx, [esi + edx*4 + 0]
    cmp edx, 0x33333333
    mov ebx, 8
    jne fail
    mov ecx, 0x00000101
    and ecx, 0x0F
    mov eax, [esi + ecx*4 + 4]
    cmp eax, 0x33333333
    mov ebx, 9
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
