; VIPT hardwired-load hit, fallback, and pointer-dependency regression.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

PTR_SLOT   equ 0x200
TARGET     equ 0x240
COLD_SLOT  equ 0x280
VALUE      equ 0x5A17C0DE
COLD_VALUE equ 0xC01DCAFE

start:
    mov esi, PTR_SLOT
    mov edi, TARGET
    mov edx, COLD_SLOT
    mov dword [esi], edi
    mov dword [edi], VALUE
    mov dword [edx], COLD_VALUE

    ; Let posted initialization stores leave the three-entry queue. Direct
    ; VIPT loads intentionally decline ownership while forwarding is needed.
    times 32 nop

    ; Populate the TLB and cache before testing direct hits.
    mov eax, [esi]
    mov ebx, [edi]
    times 16 nop

    ; A PIPT-only moffs load may retire immediately before a VIPT load. Its
    ; deferred commit must not be lost when the younger load enters EX.
    mov eax, [PTR_SLOT]
    mov ecx, [edi]
    cmp eax, TARGET
    jne fail_hit
    cmp ecx, VALUE
    jne fail_hit

    mov eax, [esi]
    mov ecx, [edi]
    cmp eax, TARGET
    jne fail_hit
    cmp ecx, VALUE
    jne fail_hit

    ; A cold load transfers to paging while the already-issued younger hit is
    ; retained and replayed after the fill.
    mov ebp, [edx]
    mov ecx, [edi]
    cmp ebp, COLD_VALUE
    jne fail_fallback
    cmp ecx, VALUE
    jne fail_fallback

    ; The second EA must observe the pointer committed by the first load.
    xor eax, eax
    xor ebx, ebx
    mov eax, [esi]
    mov ebx, [eax]
    cmp ebx, VALUE
    jne fail_pointer

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail_hit:
    mov eax, 1
    jmp fail
fail_fallback:
    mov eax, 2
    jmp fail
fail_pointer:
    mov eax, 3
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
