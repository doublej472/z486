; rep_stosd_64k.asm -- a REP STOSD of {COUNT} dwords must retire and complete.
;
; Fail-first probe for the "rep stosd-class non-retire" hang that blocks the PC-98
; userdisk tier. The instruction is ONE architectural retirement but a microcoded
; loop; the core's forward-progress watchdog assumes a repeat retires once per
; iteration. If a long repeat does not, the RTL's own assertion kills the run.
;
; Ground truth is the architectural result: ECX==0, EDI advanced by 4*COUNT, and
; the first and last dwords holding the stored value.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

DST   equ 0x20000
COUNT equ 65536

start:
    cli
    cld
    mov esp, stack_top

    mov edi, DST
    mov ecx, COUNT
    mov eax, 0xA5A5A5A5
    rep stosd

    cmp ecx, 0
    jne fail_ecx
    cmp edi, DST + COUNT * 4
    jne fail_edi
    cmp dword [DST], 0xA5A5A5A5
    jne fail_first
    cmp dword [DST + COUNT * 4 - 4], 0xA5A5A5A5
    jne fail_last

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

fail_ecx:   mov eax, 1
            jmp fail
fail_edi:   mov eax, 2
            jmp fail
fail_first: mov eax, 3
            jmp fail
fail_last:  mov eax, 4
            jmp fail

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 4
stack:
    times 256 db 0
stack_top:
