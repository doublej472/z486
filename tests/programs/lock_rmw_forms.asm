; lock_rmw_forms - every LOCK-able RMW form must read memory (stale-line method)
; Failure data = bitmask of failing checks (bit n = check n).
;
; A LOCK-prefixed RMW and XCHG with memory read memory, not a valid L1 line,
; and hold LOCK# across the read and write.  Port 0xC4/0xC8 updates RAM
; behind the caches without a snoop, so the stale line distinguishes a locked
; read (sees the RAM value) from an ordinary one (sees the line).
BITS 32
ORG 0
%macro POKE 2
    mov eax, %1
    out 0xc4, eax
    mov eax, %2
    out 0xc8, eax
%endmacro
%macro EXPECT 3
    cmp %1, %2
    je %%ok
    or edi, 1 << %3
%%ok:
%endmacro
%macro STALE 1                         ; line holds 1, RAM holds 10
    mov dword [%1], 1
    mov eax, [%1]
    POKE %1, 10
%endmacro

start:
    mov esp, 0x8000
    xor edi, edi
    STALE 0x9000
    lock add dword [0x9000], 5
    EXPECT dword [0x9000], 15, 1       ; 10 + 5, and the line is updated

    STALE 0x9100                       ; control: an ordinary RMW
    add dword [0x9100], 5
    EXPECT dword [0x9100], 6, 2

    STALE 0x9200                       ; XCHG locks without a prefix
    mov ecx, 7
    xchg [0x9200], ecx
    EXPECT ecx, 10, 3
    EXPECT dword [0x9200], 7, 4

    STALE 0x9300
    mov ebx, 3
    lock xadd [0x9300], ebx
    EXPECT ebx, 10, 5
    EXPECT dword [0x9300], 13, 6

    STALE 0x9400
    mov eax, 10
    mov ebx, 99
    lock cmpxchg [0x9400], ebx
    je ok_7
    or edi, 1 << 7
ok_7:
    EXPECT dword [0x9400], 99, 8

    STALE 0x9502                       ; misaligned: two locked reads
    lock or dword [0x9502], 0x100
    EXPECT dword [0x9502], 0x10a, 9

    STALE 0x9600                       ; LOCK INC (unary RMW)
    lock inc dword [0x9600]
    EXPECT dword [0x9600], 11, 10

    STALE 0x9700                       ; LOCK NOT
    lock not dword [0x9700]
    EXPECT dword [0x9700], 0xfffffff5, 11

    STALE 0x9800                       ; LOCK BTS
    lock bts dword [0x9800], 4
    EXPECT dword [0x9800], 26, 12

    STALE 0x9900                       ; LOCK DEC byte
    lock dec byte [0x9900]
    EXPECT dword [0x9900], 9, 13

    STALE 0x9a00                       ; LOCK ADD m, r
    mov edx, 5
    lock add [0x9a00], edx
    EXPECT dword [0x9a00], 15, 14

    STALE 0x9b00                       ; LOCK NEG
    lock neg dword [0x9b00]
    EXPECT dword [0x9b00], -10, 15

    STALE 0x9c00                       ; LOCK SUB m, r
    mov edx, 3
    lock sub [0x9c00], edx
    EXPECT dword [0x9c00], 7, 16

    test edi, edi
    jnz fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, edi                       ; bitmask of failing checks
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
