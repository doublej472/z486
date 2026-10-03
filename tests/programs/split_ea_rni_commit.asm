; Directed regression: a three-term (base + index + disp) EA whose base or
; index a multi-step recipe (MOVSX/MOVZX r,r) commits at its RNI word while
; the successor already holds its split partial sum in D2. SimCity 2000 took
; a page fault on "movsx eax,bx / mov byte [ebp+eax-0x14],0" after a taken JZ.
; EBP-based operands default to SS, so their checks address SS.
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    mov byte [0x3000], 0x0D
    mov byte [0x3010], 0x0D
    mov byte [0x3020], 0x0D
    ; case 1: the SimCity 2000 sequence (base written by MOVSX)
    mov ebp, 0x1040
    mov ebx, 3
    mov eax, 0x3000
    mov byte [ss:0x102F], 0
    cmp byte [eax], 0x0D
    jz .c1
    nop
.c1:
    movsx eax, bx
    mov byte [ebp + eax - 0x14], 0x5A
    cmp byte [ss:0x102F], 0x5A
    mov ebx, 1
    jne fail
    ; case 2: index written by MOVZX, scaled, store
    mov esi, 0x1100
    mov ecx, 2
    mov edx, 0x3010
    mov dword [0x110C], 0
    cmp byte [edx], 0x0D
    jz .c2
    nop
.c2:
    movzx edx, cx
    mov dword [esi + edx*4 + 4], 0x12345678
    cmp dword [0x110C], 0x12345678
    mov ebx, 2
    jne fail
    ; case 3: index written by MOVSX, load
    mov dword [0x1208], 0xCAFEF00D
    mov edi, 0x1200
    mov ecx, 1
    mov eax, 0x3020
    cmp byte [eax], 0x0D
    jz .c3
    nop
.c3:
    movsx eax, cx
    mov edx, [edi + eax*4 + 4]
    cmp edx, 0xCAFEF00D
    mov ebx, 3
    jne fail
    ; case 4: back to back, no branch before the MOVSX
    mov ebp, 0x1300
    mov eax, 0x3000
    mov ebx, 5
    mov byte [ss:0x12F1], 0
    movsx eax, bx
    mov byte [ebp + eax - 0x14], 0xA5
    cmp byte [ss:0x12F1], 0xA5
    mov ebx, 4
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
