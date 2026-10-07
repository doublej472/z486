; arpl_idle_rpt - an idle microsequencer must not freeze on a read-ahead RPT word
;
; ARPL's protection test ends with a RPT word (6B7h) that repeats while
; COUNTR != 0 or the test is in flight.  When ARPL retires and the next
; instruction is slow to issue, the ROM read-ahead reached 6B7h while the
; sequencer was idle; with a stale nonzero COUNTR (left by MOV CR0) the repeat
; condition froze the ROM output, and the next instruction then executed the
; frozen word forever.  Memory latency 10 delays the next issue long enough
; with either response model.
; Results: port 0xE0 status (0x01 pass / 0xFF fail).
BITS 32
ORG 0
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 08: code, base 0x10000
    dq 0x00cf93000000ffff     ; 10: data, base 0
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt
times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site0
    align 16
    times 14 db 0x90
site0:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site1
    align 16
    times 14 db 0x90
site1:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 1 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site2
    align 16
    times 14 db 0x90
site2:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 2 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site3
    align 16
    times 14 db 0x90
site3:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 3 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site4
    align 16
    times 14 db 0x90
site4:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 4 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site5
    align 16
    times 14 db 0x90
site5:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 5 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site6
    align 16
    times 14 db 0x90
site6:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 6 nop
    mov eax, cr0
    mov cr0, eax               ; COUNTR <- {PG,PE} (nonzero)
    xor eax, eax
    mov dword [0x6000], 0
    mov dword [0x6004], 0
    jmp short site7
    align 16
    times 14 db 0x90
site7:
    db 0x63, 0xc0              ; ARPL ax, ax: last two bytes of a line
    mov esp, 0x8000            ; first instruction of the next line
    mov ax, 0x10
    mov ds, ax
    times 7 nop
    mov al, 1
    out 0xe0, al
    hlt
