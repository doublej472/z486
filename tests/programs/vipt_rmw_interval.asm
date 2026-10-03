; RD_FAST interval regression.  Each chain starts with a store to the same
; dword, so the first RMW's D2 preread can be denied while that store is in L1
; lookup.  The overlay must replay the preread (one clock), not fall back to
; the original 04A/04E routine, whose own store would then deny the next
; RMW's preread and keep the whole chain slow (v71 M1: 15 clocks each).
;
; Port 0xFC reads the testbench cycle counter.  Each chain of eight RMWs is
; timed against an empty bracket containing the same store, and must add at
; most MAX_CHAIN clocks (measured 18-30 at v71 M1; a fallback chain adds ~100).

BITS 32
org 0

STATUS_PORT equ 0xE0
CYCLE_PORT  equ 0xFC
DATA_PORT   equ 0xE4
MAX_CHAIN   equ 8*4                 ; i486 cadence is 3; allow bracket drain noise

MX      equ 0x1040
MB      equ 0x1080

; TIME_CHAIN op, init, expect, fail_value, fail_time
%macro TIME_CHAIN 5
    mov eax, [MX]                ; warm line and TLB
    times 8 nop
    in eax, CYCLE_PORT
    mov esi, eax
    mov dword [MX], %2
    in eax, CYCLE_PORT
    sub eax, esi
    mov ebp, eax                 ; bracket overhead, including the store
    times 8 nop
    in eax, CYCLE_PORT
    mov esi, eax
    mov dword [MX], %2
    %1
    %1
    %1
    %1
    %1
    %1
    %1
    %1
    in eax, CYCLE_PORT
    sub eax, esi
    sub eax, ebp
    out DATA_PORT, eax           ; report the measured chain clocks
    cmp dword [MX], %3
    jne %4
    cmp eax, MAX_CHAIN
    ja %5
%endmacro

start:
    mov edi, MX
    ; Dirty the page and warm the line through the slow path first.
    mov dword [MX], 0
    mov dword [MB], 0
    times 32 nop

    TIME_CHAIN {inc dword [edi]}, 0x10, 0x18, fail2, fail3
    TIME_CHAIN {dec dword [edi]}, 0x10, 0x08, fail4, fail5
    TIME_CHAIN {not dword [edi]}, 0x12345678, 0x12345678, fail6, fail7
    TIME_CHAIN {neg dword [edi]}, 5, 5, fail8, fail9
    mov ecx, 1
    TIME_CHAIN {add dword [edi], ecx}, 0x100, 0x108, fail10, fail11

    ; A byte-sized unary chain takes the same overlay.
    mov eax, [MB]
    times 8 nop
    in eax, CYCLE_PORT
    mov esi, eax
    mov byte [MB], 0xf0
    in eax, CYCLE_PORT
    sub eax, esi
    mov ebp, eax
    times 8 nop
    in eax, CYCLE_PORT
    mov esi, eax
    mov byte [MB], 0xf0
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    inc byte [edi+MB-MX]
    in eax, CYCLE_PORT
    sub eax, esi
    sub eax, ebp
    out DATA_PORT, eax
    cmp byte [MB], 0xf8
    jne fail12
    cmp eax, MAX_CHAIN
    ja fail13

pass:
    mov al, 1
    out STATUS_PORT, al
    hlt

fail2:  mov eax, 2
    jmp fail
fail3:  mov eax, 3
    jmp fail
fail4:  mov eax, 4
    jmp fail
fail5:  mov eax, 5
    jmp fail
fail6:  mov eax, 6
    jmp fail
fail7:  mov eax, 7
    jmp fail
fail8:  mov eax, 8
    jmp fail
fail9:  mov eax, 9
    jmp fail
fail10: mov eax, 10
    jmp fail
fail11: mov eax, 11
    jmp fail
fail12: mov eax, 12
    jmp fail
fail13: mov eax, 13
fail:
    out STATUS_PORT, al
    hlt
