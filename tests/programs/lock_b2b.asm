; lock_b2b - LOCK# must cover the read and write of a locked RMW that
; starts while the previous locked instruction's lock is still draining
;
; LOCK BTS's posted write is still leaving the CPU when LOCK XADD's locked read
; is accepted (the setup stores keep the store queue busy).  The
; lock-honouring external master (+xdma_*) arms on XADD's read of 0x9140 and
; writes 0x9140 = 100 as soon as LOCK# is low.  On a 486 LOCK# stays asserted
; until XADD's write, so memory ends at 100 (external write after the RMW),
; never 2 (the RMW of the stale 1 overwriting the external write).
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov ecx, 1
    mov dword [0x9000], 1
    mov dword [0x9040], 1
    mov dword [0x9080], 1
    mov dword [0x90c0], 1
    mov dword [0x9100], 1
    mov dword [0x9140], 1
    mov dword [0x9180], 1
    mov dword [0x91c0], 1
    mov dword [0x9200], 1
    mov dword [0x9240], 1
    mov eax, [0x9500]            ; spacer
    lock add [0x9000], ecx       ; 01 /r
    nop
    nop
    lock add dword [0x9040], 5   ; 83 /0
    nop
    nop
    lock inc dword [0x9080]      ; FF /0
    nop
    nop
    lock not dword [0x90c0]      ; F7 /2
    nop
    nop
    lock bts dword [0x9100], 3   ; 0F BA /5
    nop
    nop
    lock xadd [0x9140], ecx      ; 0F C1
    nop
    nop
    mov ecx, 200
spin:
    loop spin
    mov eax, [0x9140]
    out 0xe4, eax
    cmp eax, 2
    je fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
