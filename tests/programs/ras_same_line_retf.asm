; ras_same_line_retf.asm - a near RET whose return-address-stack prediction is WRONG
; but lands in the SAME 16-byte line as the real target must resume at the real target.
;
; Shape of Touhou 5 OP.EXE's packfile reader (rec98 master.lib pf): `call R`; R builds a
; far frame (`push cs; call near F`) and F returns with RETF, which pops no RAS entry, so
; R's own `ret` predicts L (the return of `call F`) while the stack holds `after` (the
; return of `call R`), 4 bytes later in the same line. Before the fix prefetch.sv compared
; only the line ([31:4]) for a RET owner and seeded the adopted line from the PREDICTED
; offset, so the CPU re-executed the `ret` at L and popped the marker below: FAIL.
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, 0xFF00
    mov cx, 200                ; repeat: the spec line must be buffered at least once
again:
    push word bad              ; the word a phantom second `ret` would pop
    jmp near go
    align 16
R:  push cs                    ; line +0
    call near F                ; line +1..+3, RAS push L
L:  ret                        ; line +4: RAS predicts L, the stack says `after`
go: call near R                ; line +5..+7, RAS push `after`
after:                         ; line +8: the real target
    add sp, 2                  ; drop the marker
    loop again
    mov al, 0x01
    out STATUS_PORT, al
    hlt
F:  retf
bad:
    mov ax, cx
    out DATA_PORT, ax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
