; cr3_walk_race_same.asm - a same-value CR3 reload with a prefetch walk in
; flight. The walk is re-done under the same tables; [N_j] must read P_{j+1}'s
; marker. Same page layout as cr3_walk_race.asm, identity map only.
BITS 32
ORG 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CSBASE      equ 0x10000
NTRIALS     equ 32

%define P(j)    (0x11000 + (j)*0x1000)
%define N(j)    (P(j) + 0x1000)

start:
    mov esp, 0x0003F000
%assign j 0
%rep NTRIALS
    xor eax, eax
    jmp stub_ %+ j
back_ %+ j:
    mov eax, [N(j)]
    cmp eax, 0xA0000000 + j
    jne fail
%assign j j+1
%endrep
    mov al, 0x01
    out STATUS_PORT, al
    hlt
fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

; Page P_0 .. P_{NTRIALS}: each begins with the previous page's OLD marker
; and ends with the trial stub.
%assign j 0
%rep NTRIALS+1
    times (P(j) - CSBASE) - ($ - $$) db 0
    dd 0xA0000000 + j - 1
%if j < NTRIALS
    times (P(j) + 0x1000 - CSBASE) - ($ - $$) - 8 - (j % 16) - 16 db 0
  %if j >= 16
    times 16 nop
  %else
    times 16 db 0
  %endif
stub_ %+ j:
    mov cr3, eax              ; eax = 0, the value already in CR3
    jmp back_ %+ j
    times (j % 16) db 0x90
%endif
%assign j j+1
%endrep
    times (P(NTRIALS) + 0x1000 - CSBASE) - ($ - $$) db 0
