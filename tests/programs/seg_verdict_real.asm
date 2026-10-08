; seg_verdict_real.asm - PC-98 DIAGNOSTIC (re-vendor regression guard).
;
; Real-mode direct-load / store SEGMENT VERDICT at the 64K segment boundary.
; Touhou 5's OOM path (`mov word [9ECh],5208h` -> `mov bx,[9ECh]` -> INT 21h
; AH=48h -> the MCB-chain walk) runs entirely in real mode, but the c244785
; re-vendor's "direct-load segment verdict" fix is pinned only by PROTECTED-mode
; programs (seg_limit_older_commit, seg_limit_stall_d2). This program drives the
; same verdict in real mode: a word load and store at offset 0xFFFE (the top two
; bytes of a 64K segment, both in bounds) must NOT fault and must round-trip
; exactly.
;
; Expected values are ARCHITECTURAL (real mode: linear = DS<<4 + 16-bit offset;
; a word at offset 0xFFFE spans 0xFFFE..0xFFFF, inside the segment, so there is
; no 64K wrap and no fault), NOT derived from this core.
;
; Port 0xE0: 0x01 = pass, 0xFF = fail. Port 0xE4 = failing case number.
;
; NOT in the upstream fork: this is a PC-98 diagnostic. If it proves a bug,
; push it upstream to the upstream CPU tree.

BITS 16
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

TOUHOU_REQ  equ 0x5208        ; Touhou 5's paragraph request (symbolic)

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ds, ax

    ; -- case 1: word store then word load at offset 0xFFFE (DS = 0) --------
    mov word [0xFFFE], TOUHOU_REQ
    mov ax, [0xFFFE]
    cmp ax, TOUHOU_REQ
    jne fail1

    ; -- case 2: byte load at the very last offset (0xFFFF) -----------------
    ;   little-endian: the high byte of the stored word lives at 0xFFFF.
    mov al, [0xFFFF]
    cmp al, 0x52
    jne fail2

    ; -- case 3: byte store at the very last offset, then reload -------------
    mov byte [0xFFFF], 0x7E
    mov al, [0xFFFF]
    cmp al, 0x7E
    jne fail3

    ; -- case 4: second word pattern at the boundary (store -> load) ---------
    mov word [0xFFFE], 0x4321
    mov bx, [0xFFFE]
    cmp bx, 0x4321
    jne fail4

    ; -- case 5: register-indirect load/store at the boundary ---------------
    mov si, 0xFFFE
    mov word [si], 0xABCD
    mov cx, [si]
    cmp cx, 0xABCD
    jne fail5

    ; -- case 6: non-zero DS base: linear = DS<<4 + offset -------------------
    mov ax, 0x1000
    mov ds, ax
    mov word [0xFFFE], 0x3142
    mov dx, [0xFFFE]
    cmp dx, 0x3142
    jne fail6

    xor ax, ax
    mov ds, ax

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail1: mov ax, 1
       jmp fail
fail2: mov ax, 2
       jmp fail
fail3: mov ax, 3
       jmp fail
fail4: mov ax, 4
       jmp fail
fail5: mov ax, 5
       jmp fail
fail6: mov ax, 6
       jmp fail

fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
