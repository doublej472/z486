; cache_ctrl_486 - 486 cache operating modes (CR0.CD/NW) and page-level PCD
;
; Each case uses its own L1 set so replacement cannot evict a control line.
; Port 0xC4/0xC8 writes RAM behind both L1s without a snoop, so a stale line
; shows whether a read or fetch was served from the cache.  Every case keeps a
; cacheable control that must observe the stale line.
;   - PTE.PCD: a read or fetch miss is not allocated; a valid line still hits.
;   - CR0.CD=1: no line is allocated; valid lines continue to respond.
;   - CR0.CD=1, NW=1: a write hit updates only the cache (INVD loses it);
;     a write miss goes to memory.
;   - PDE.PCD: the page-table read of a walk is not allocated.
BITS 32
ORG 0
CODE_BASE equ 0x10000
PT0       equ 0x1000                ; page table for linear 0-4 MB
%define PTE(lin) (PT0 + ((lin) >> 12) * 4)
PCD       equ 0x10

%macro POKE 2
    mov eax, %1
    out 0xc4, eax
    mov eax, %2
    out 0xc8, eax
%endmacro
%macro EXPECT 3
    cmp %1, %2
    jne fail_%3
%endmacro

start:
    mov esp, 0x9000
    wbinvd

    ; 1: cacheable control - the poked value is hidden by the valid line.
    mov dword [0x20100], 0x11111111
    mov eax, [0x20100]
    POKE 0x20100, 0xaaaaaaaa
    mov ebx, [0x20100]
    EXPECT ebx, 0x11111111, 1

    ; 2: PCD page - the miss is not allocated, so the poke is seen.
    mov dword [0x21200], 0x22222222
    or dword [PTE(0x21200)], PCD
    invlpg [0x21200]
    mov eax, [0x21200]
    EXPECT eax, 0x22222222, 2
    POKE 0x21200, 0xbbbbbbbb
    mov ebx, [0x21200]
    EXPECT ebx, 0xbbbbbbbb, 3

    ; 3: PCD does not bypass a line that is already valid.
    mov dword [0x22300], 0x33333333
    mov eax, [0x22300]
    or dword [PTE(0x22300)], PCD
    invlpg [0x22300]
    POKE 0x22300, 0xcccccccc
    mov ebx, [0x22300]
    EXPECT ebx, 0x33333333, 4

    ; 4: CR0.CD=1 - new lines are not allocated, valid lines still hit.
    mov dword [0x23400], 0x44444444
    mov ecx, cr0
    or ecx, 0x40000000
    mov cr0, ecx
    mov eax, [0x23400]
    EXPECT eax, 0x44444444, 5
    POKE 0x23400, 0xdddddddd
    mov ebx, [0x23400]
    EXPECT ebx, 0xdddddddd, 6
    mov ebx, [0x20100]                ; line from case 1 is still valid
    EXPECT ebx, 0x11111111, 7
    and ecx, ~0x60000000
    mov cr0, ecx

    ; 5: CD=1 NW=1 - write hits stay in the cache, write misses reach memory.
    wbinvd
    mov eax, [0x20100]                ; allocate (memory holds 0xaaaaaaaa)
    EXPECT eax, 0xaaaaaaaa, 8
    or ecx, 0x60000000
    mov cr0, ecx
    mov dword [0x20100], 0x55555555   ; hit: cache only
    mov eax, [0x20100]
    EXPECT eax, 0x55555555, 9
    mov dword [0x24500], 0x66666666   ; miss: memory
    invd                              ; drop the never-written line
    mov eax, [0x20100]
    EXPECT eax, 0xaaaaaaaa, 10
    mov eax, [0x24500]
    EXPECT eax, 0x66666666, 11
    and ecx, ~0x60000000
    mov cr0, ecx

    ; 6: instruction fetch from a PCD page is not allocated in the I-cache.
    mov dword [0x30600], 0x000001b8   ; mov eax, 1 / ret
    mov dword [0x30604], 0x0000c300
    mov dword [0x31700], 0x000001b8
    mov dword [0x31704], 0x0000c300
    or dword [PTE(0x30600)], PCD
    invlpg [0x30600]
    call (0x30600 - CODE_BASE)
    EXPECT eax, 1, 12
    call (0x31700 - CODE_BASE)
    EXPECT eax, 1, 13
    POKE 0x30600, 0x000002b8          ; mov eax, 2
    POKE 0x31700, 0x000002b8
    call (0x30600 - CODE_BASE)
    EXPECT eax, 2, 14
    call (0x31700 - CODE_BASE)        ; cacheable control: stale line
    EXPECT eax, 1, 15

    ; 7: PDE.PCD - the page-table read of a walk is not allocated.
    or dword [0x0000], PCD            ; PDE 0
    mov eax, cr3                      ; flush the TLB
    mov cr3, eax
    wbinvd                            ; and any page-table line
    mov dword [0x26a00], 0x77777777
    mov dword [0x27a00], 0x88888888
    mov eax, [0x25a00]                ; walk reads PTE(0x25000) uncached
    POKE PTE(0x25000), 0x00026063     ; remap 0x25000 -> 0x26000, no snoop
    invlpg [0x25a00]
    mov eax, [0x25a00]
    EXPECT eax, 0x77777777, 16
    and dword [0x0000], ~PCD
    mov eax, cr3
    mov cr3, eax
    mov eax, [0x25a00]                ; PT line now allocated by this walk
    POKE PTE(0x25000), 0x00027063
    invlpg [0x25a00]
    mov eax, [0x25a00]                ; control: walker sees the stale PTE
    EXPECT eax, 0x77777777, 17

    mov al, 1
    out 0xe0, al
    hlt

%assign c 1
%rep 17
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
