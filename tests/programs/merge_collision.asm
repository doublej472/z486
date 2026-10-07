; merge_collision - drive a deferred load token and a recipe-commit PULSE at the
; same register in the same cycle.
;
; gpr_write_merge arbitrates {shift,mem,rom,load-wb,dly}, but three recipe
; commits write the register file AFTER commit_merged and appear in NO view:
; RECIPE_COMMIT_SIGSRC (MOVZX/MOVSX, SIGMA->SRCREG), RECIPE_COMMIT_ESP (PUSH)
; and the REP-STOS ECX write.  If one lands on a register an older, still-live
; memory token owns, the register file keeps the pulse while every forwarding
; view keeps the token - the P1 shape that showed up as a spurious page fault.
;
; Every access walks a fresh cache line so the load stays in flight (cold-line
; fill, reachable only because the bench now answers line_read).
;
; Self-checking: each result is compared against the same value produced by a
; second, independent instruction sequence, so no external model is needed.
BITS 32
ORG 0
STATUS_PORT equ 0xE0
BUF   equ 0x00020000          ; stride 64 -> every access a cold line
BUF2  equ 0x00030000          ; same, but every dword holds STACK
STACK equ 0x0000FF00
NRUNS equ 150

start:
    cli
    mov esp, STACK

;--- prefill: dword[i] = (i<<8)|0x81, so AH = i&0xFF and AL = 0x81 (signs set)
    xor  ecx, ecx
fill:
    mov  eax, ecx
    shl  eax, 8
    or   eax, 0x00000081
    mov  dword [BUF + ecx*4], eax
    inc  ecx
    cmp  ecx, NRUNS*16
    jb   fill

;--- prefill BUF2 with a valid stack base so MOV ESP,[mem] is safe
    xor  ecx, ecx
fill2:
    mov  dword [BUF2 + ecx*4], STACK
    inc  ecx
    cmp  ecx, NRUNS*16
    jb   fill2

;=== A: MOVZX/MOVSX (sigma-src pulse) vs a live load token on the SAME register
    mov  edi, BUF
    xor  ecx, ecx
loopA:
    mov  eax, [edi]           ; hardwired load, cold line -> token on EAX
    movzx eax, ah             ; SIGSRC commit, SRCREG = EAX  <-- collision
    mov  ebx, [edi]           ; independent reference
    shr  ebx, 8
    movzx ebx, bl
    cmp  eax, ebx
    jne  fail
    mov  eax, [edi]
    movsx eax, al             ; AL = 0x81 -> must sign-extend to 0xFFFFFF81
    mov  ebx, [edi]
    movsx ebx, bl
    cmp  eax, ebx
    jne  fail
    add  edi, 64
    inc  ecx
    cmp  ecx, NRUNS
    jb   loopA

;=== B: PUSH (ESP pulse) vs a live load token whose destination IS ESP
    mov  edi, BUF
    xor  ecx, ecx
loopB:
    mov  edi, BUF2
loopB1:
    mov  esp, STACK           ; known-good stack base every iteration
    mov  esp, [edi]           ; cold-line load whose destination is ESP
    cmp  esp, STACK
    jne  fail
    push eax                  ; RECIPE_COMMIT_ESP pulse on ESP  <-- collision
    pop  edx
    cmp  edx, eax
    jne  fail
    add  edi, 64
    cmp  edi, BUF2 + NRUNS*16*4
    jb   loopB1

    mov  esp, STACK
    mov  al, 1
    mov  dx, STATUS_PORT
    out  dx, al
    hlt
fail:
    mov  al, 0xFF
    mov  dx, STATUS_PORT
    out  dx, al
    hlt
