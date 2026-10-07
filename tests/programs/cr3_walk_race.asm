; cr3_walk_race.asm - a prefetch walk in flight across MOV CR3 must not install
; the old address space's translation.
;
; Each trial ends a code page P_j with "mov cr3,eax ; jmp back_j" so the
; prefetcher walks the next page N_j around the CR3 write. A (CR3=0) maps N_j
; to itself; B (PD_B) maps it to NEWF_j. After switching A->B, [N_j] must read
; B's marker.
BITS 32
ORG 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CSBASE      equ 0x10000
NTRIALS     equ 32
PFLAGS      equ 0x23
%define P(j)    (0x11000 + (j)*0x1000)
%define N(j)    (P(j) + 0x1000)
%define NEWF(j) (0x60000 + (j)*0x1000)
%define PTE(a)  (0x1000 + ((a) >> 12)*4)

PD_B        equ 0x2000
PT_B        equ 0x3000
start:
    mov esp, 0x0003F000
    ; Address space B: PD_B[0] -> PT_B, PT_B = copy of the generated PT_A at
    ; 0x1000 with every N_j redirected to NEWF_j. CR3=0 (A) keeps identity.
    cld
    mov esi, 0x1000
    mov edi, PT_B
    mov ecx, 1024
    rep movsd
    mov edi, PD_B
    xor eax, eax
    mov ecx, 1024
    rep stosd
    mov dword [PD_B], PT_B | PFLAGS
%assign j 0
%rep NTRIALS
    mov dword [NEWF(j)], 0xB0000000 + j
%assign j j+1
%endrep

%assign j 0
%rep NTRIALS
    mov dword [PT_B + (N(j) >> 12)*4], NEWF(j) | PFLAGS
    mov eax, PD_B
    jmp stub_ %+ j
back_ %+ j:
    mov eax, [N(j)]
    cmp eax, 0xB0000000 + j
    jne fail
    xor eax, eax
    mov cr3, eax
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

; Page P_0 .. P_{NTRIALS}: each begins with the previous trial's OLD marker
; (it is N_{j-1}) and ends with trial j's stub.
%assign j 0
%rep NTRIALS+1
    times (P(j) - CSBASE) - ($ - $$) db 0
    dd 0xA0000000 + j - 1          ; OLD marker of N_{j-1}
%if j < NTRIALS
    ; D_j = j % 16 bytes of padding after the stub, before the page end;
    ; j >= 16 also puts 16 NOPs ahead of the stub (a different fetch phase).
    times (P(j) + 0x1000 - CSBASE) - ($ - $$) - 8 - (j % 16) - 16 db 0
  %if j >= 16
    times 16 nop
  %else
    times 16 db 0
  %endif
stub_ %+ j:
    mov cr3, eax
    jmp back_ %+ j
    times (j % 16) db 0x90
%endif
%assign j j+1
%endrep
    times (P(NTRIALS) + 0x1000 - CSBASE) - ($ - $$) db 0
