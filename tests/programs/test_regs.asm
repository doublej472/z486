; test_regs - 486 test registers TR3-TR7
;
; TR6/TR7 drive the TLB: a TR6 write with C=0 installs an entry from TR6/TR7
; (the entry is used for translation), and with C=1 looks one up, reporting
; PFN/PCD/PWT, PL (hit) and REP (way) in TR7.  TR3-TR5 are the cache test
; registers (absent on the 80386); TR5.CTL=11 invalidates the cache.
BITS 32
ORG 0
PT0 equ 0x1000
%macro EXPECT 3
    cmp %1, %2
    jne fail_%3
%endmacro
%macro POKE 2
    mov eax, %1
    out 0xc4, eax
    mov eax, %2
    out 0xc8, eax
%endmacro

start:
    mov esp, 0x8000
    ; 1: TR3-TR5 hold their writable bits.
    mov eax, 0x12345678
    mov tr3, eax
    mov ecx, tr3
    EXPECT ecx, 0x12345678, 1
    mov eax, 0xffffffff
    mov tr4, eax
    mov ecx, tr4
    EXPECT ecx, 0xfffffc00, 2
    mov eax, 0xfffffff4                ; CTL=00: no operation
    mov tr5, eax
    mov ecx, tr5
    EXPECT ecx, 0x000007f4, 3

    ; 2: look up a walked translation (V=1, attributes don't care).
    mov eax, [0x23000]                 ; walk fills the TLB
    mov eax, 0x00023fe1                ; linear 0x23000, V, D/D# U/U# W/W# = 11, C
    mov tr6, eax
    mov ecx, tr7
    test ecx, 0x10                     ; PL: single hit
    jz fail_4
    and ecx, 0xfffff000
    EXPECT ecx, 0x00023000, 5

    ; 3: a lookup that misses reports PL=0.
    mov eax, 0x7f000fe1
    mov tr6, eax
    mov ecx, tr7
    test ecx, 0x10
    jnz fail_6

    ; 4: install linear 0x24000 -> physical 0x26000 in way 2 (no PTE change).
    mov dword [0x26100], 0xabcd1234
    mov dword [0x24100], 0x11111111
    invlpg [0x24000]                   ; no duplicate tag in the TLB
    mov eax, 0x00026c18                ; PA 0x26000, PCD, PWT, PL, REP=2
    mov tr7, eax
    mov eax, 0x00024d40                ; linear 0x24000, V, D, U, W, C=0
    mov tr6, eax
    mov eax, [0x24100]
    EXPECT eax, 0xabcd1234, 7          ; the installed entry translates
    mov eax, 0x00024fe1                ; look it up again
    mov tr6, eax
    mov ecx, tr7
    mov edx, ecx
    and edx, 0xfffffc1c
    EXPECT edx, 0x00026c18, 8          ; PFN, PCD, PWT, PL, REP=2
    mov ecx, tr6
    and ecx, 0x00000fe0
    EXPECT ecx, 0x00000d40, 9          ; V, D, U, W reported as pairs
    invlpg [0x24000]                   ; back to the page tables
    mov eax, [0x24100]
    EXPECT eax, 0x11111111, 10

    ; 5: TR5.CTL=11 flushes the cache.
    mov dword [0x25100], 0x22222222
    mov eax, [0x25100]                 ; allocate
    POKE 0x25100, 0x33333333           ; behind the line, no snoop
    mov eax, [0x25100]
    EXPECT eax, 0x22222222, 11
    mov eax, 0x00000003
    mov tr5, eax
    mov eax, [0x25100]
    EXPECT eax, 0x33333333, 12

    mov al, 1
    out 0xe0, al
    hlt

%assign c 1
%rep 12
fail_ %+ c:
    mov eax, c
    jmp fail
%assign c c+1
%endrep
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
