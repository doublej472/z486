; flags_restore.asm - real-mode FLAGS/EFLAGS restoration round-trips.
;
; Adapted from the Zet98 reference at d4a3789 (tests/hardware/flags_probe.asm,
; "Real-mode FLAGS/EFLAGS restoration and exact single-step return address").
; The single-step half of that probe is already covered (and exceeded) by this
; suite's tf_single_step_rm, so this adaptation carries the three RESTORATION
; round-trips only: PUSHF/POPF through the 0x0CD5 low-flag mask, PUSHFD/POPFD
; through 0x040CD5 (adding the 486's AC flag), and SAHF/LAHF through 0x0D5.
;
; Expected values are architectural (a flag write must read back identically;
; the reserved bit 1 is forced to 1, which is why `or ax,2` is applied to both
; the value written and the comparison) -- never from this core's RTL.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000

    xor si, si
    mov di, 1024

.roundtrip:
    ; stage 1: PUSHF/POPF round-trips the low flags (mask 0x0CD5).
    mov byte [stage], 1
    mov ax, si
    and ax, 0cd5h
    or  ax, 2
    push ax
    popf
    pushf
    pop dx
    xor dx, ax
    test dx, 0cd5h
    jnz failed

    ; stage 2: PUSHFD/POPFD round-trips the low flags and AC (mask 0x040CD5).
    mov byte [stage], 2
    movzx eax, si
    shl eax, 18
    and eax, 40000h              ; AC = si bit 0
    mov bx, si
    and bx, 0cd5h
    or  bx, 2
    mov ax, bx
    push eax
    popfd
    pushfd
    pop edx
    xor edx, eax
    test edx, 40cd5h
    jnz failed

    ; stage 3: SAHF/LAHF round-trips the low flags.
    mov byte [stage], 3
    mov ax, si
    and ax, 0ffh
    mov ah, al
    sahf
    lahf
    and al, 0d5h
    or  al, 2
    cmp al, ah
    jne failed

    inc si
    dec di
    jnz .roundtrip

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

failed:
    mov dx, DATA_PORT
    movzx eax, byte [stage]
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

stage: db 0
