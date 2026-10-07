; A cold ROM POP followed immediately by a warm VIPT ALU read of the same
; register. Non-flat SS keeps POP on the ROM path. This is an integration
; guard; tb_data_access injects the precise stale-token fallback condition.
BITS 32
ORG 0
start:
    mov ebp, 0x1c
    mov dword [ss:0x10], 0xffff00ff
    mov dword [ss:0x2000], 0x12345678
    mov dword [ss:0x2800], 0xdeadbeef
    mov dword [ss:0x3000], 0xdeadbeef
    mov dword [ss:0x3800], 0xdeadbeef
    mov dword [ss:0x4000], 0xdeadbeef
    ; Warm the TLB, then evict the first line from its four-way D-cache set.
    mov ecx, [ss:0x2000]
    mov ecx, [ss:0x2800]
    mov ecx, [ss:0x3000]
    mov ecx, [ss:0x3800]
    mov ecx, [ss:0x4000]
    mov edi, [ebp-12]         ; warm successor, different set (default SS)
    mov esp, 0x2000
    times 16 nop
    align 16
    pop eax
    and eax, [ebp-12]         ; 12345678 & ffff00ff = 12340078
    cmp eax, 0x12340078
    jne fail
    cmp esp, 0x2004
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
