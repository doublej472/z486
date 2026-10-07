; lock_ltr_busy - LTR's busy-bit update vs an external write
;
; LTR marks the TSS descriptor busy.  The testbench's external master
; (+xdma_*) writes the descriptor's high dword right after the CPU reads the
; descriptor.  A 486 sets B with a locked read-modify-write, so the external
; write (base[31:24] = 12h) is never lost, and B is set.
; (derived from lock_desc_abit)
BITS 32
ORG 0
GDT equ 0x9800
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff        ; 0x08: code, base 0x10000 (current CS)
    mov dword [GDT+12], 0x00cf9a01
    mov dword [GDT+16], 0x0000ffff       ; 0x10: flat data
    mov dword [GDT+20], 0x00cf9200
    mov dword [GDT+24], 0xa0000067       ; 0x18: available 386 TSS at 0xA000
    mov dword [GDT+28], 0x00008900
    mov word [0x9700], 31
    mov dword [0x9702], GDT
    lgdt [0x9700]
    invd                                  ; descriptor table not in the L1
    mov ax, 0x18
    ltr ax                                ; descriptor read + busy-bit write
    invd                                  ; see RAM, not a stale line
    mov eax, [es:GDT+28]
    out 0xe4, eax
    cmp eax, 0x12008b00                   ; external base[31:24] and B=1
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
