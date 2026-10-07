; lock_rmw - 486 locked read-modify-write cycles
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
    jne fail_%3
%endmacro
%macro STALE 1                         ; line holds 1, RAM holds 10
    mov dword [%1], 1
    mov eax, [%1]
    POKE %1, 10
%endmacro

start:
    mov esp, 0x8000
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
    jne fail_7
    EXPECT dword [0x9400], 99, 8

    STALE 0x9502                       ; misaligned: two locked reads
    lock or dword [0x9502], 0x100
    EXPECT dword [0x9502], 0x10a, 9

    mov al, 1
    out 0xe0, al
    hlt

%assign c 1
%rep 9
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
