; ed_stack_real.asm - PC-98 DIAGNOSTIC (re-vendor regression guard).
;
; Real-mode SS stack round-trip. The bdca3b9 re-vendor added expand-down (ED)
; segment handling to the limit checks, and its fail-first regression
; (ed_seg_limit_check) is PROTECTED-mode only. This program guards the real-mode
; side: in real mode the hidden SS descriptor is NOT expand-down, so a `mov ss,ax`
; + `mov sp` + push/pop must behave as a normal, wrap-capable 64K stack. A
; regression that flips the ED verdict (or the stack limit) would make push/pop
; fault or round-trip a wrong value.
;
; Expected values are ARCHITECTURAL (real-mode push: SP -= 2 then word store at
; SS:SP; pop: word load at SS:SP then SP += 2; SP wraps mod 64K), NOT derived
; from this core.
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

start:
    cli
    xor ax, ax
    mov ss, ax
    mov ds, ax

    ; -- case 1: ordinary stack, SP = 0x1000 --------------------------------
    mov sp, 0x1000
    mov ax, 0x5208
    push ax
    pop bx
    cmp bx, 0x5208
    jne fail1

    ; -- case 2: SP = 0 wrap: push decrements to 0xFFFE (mod 64K) ------------
    mov sp, 0x0000
    mov ax, 0x1234
    push ax
    pop bx
    cmp bx, 0x1234
    jne fail2

    ; -- case 3: non-zero SS base via `mov ss,ax` (SBRM path), SP = 0 wrap ----
    mov ax, 0x1000
    mov ss, ax
    mov sp, 0x0000
    mov ax, 0x3142
    push ax
    pop bx
    cmp bx, 0x3142
    jne fail3

    ; restore the zero-segment stack before reporting
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

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

fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
