; dma_flush_patchq - a whole-L1 flush must drop the I-cache's store-patch queue
;
; The PC-98 platform ties the snoop input off and keeps DMA coherent with the
; native whole-L1 flush (port 0xC0 here).  The I-cache keeps the last three
; D-cache store patches (patchq) and merges them into every later line fill.
; Case 1: the CPU writes a stub "mov eax,1 / ret", DMA (0xC4/0xC8, no snoop)
; replaces it with "mov eax,2 / ret", the platform flushes, the CPU calls it:
; a 486 executes the DMA'd code (eax=2).
; Case 2 (control): three unrelated stores turn the patch queue over first.
; Failure data = bitmask of failing cases (bit 1 = case 1, bit 2 = case 2).
BITS 32
ORG 0
CODE_BASE equ 0x10000
%macro POKE 2
    mov eax, %1
    out 0xc4, eax
    mov eax, %2
    out 0xc8, eax
%endmacro
%macro PLATFORM_FLUSH 0
    out 0xc0, al
%%w: in al, 0xc0
    test al, 1
    jz %%w
%endmacro

start:
    mov esp, 0x8000
    xor edi, edi                      ; bit n = case n failed

    push eax                          ; warm the stack page (TLB, A/D bits)
    pop eax
    ; ---- case 1 ----
    mov dword [0x30004], 0x0000c300   ; ret
    mov dword [0x30000], 0x000001b8   ; mov eax, 1
    POKE 0x30000, 0x000002b8          ; DMA: mov eax, 2
    PLATFORM_FLUSH
    call (0x30000 - CODE_BASE)
    cmp eax, 2
    je ok_1
    or edi, 2
ok_1:

    ; ---- case 2 (control) ----
    mov dword [0x31004], 0x0000c300
    mov dword [0x31000], 0x000001b8
    POKE 0x31000, 0x000002b8
    PLATFORM_FLUSH
    mov dword [0x9000], 1             ; three unrelated stores
    mov dword [0x9010], 2
    mov dword [0x9020], 3
    call (0x31000 - CODE_BASE)
    cmp eax, 2
    je ok_2
    or edi, 4
ok_2:

    test edi, edi
    jnz fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, edi                      ; failing-case bitmask
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
