; lock_desc_abit - descriptor accessed-bit update vs an external write
;
; Loading DS from a descriptor with A=0 makes the CPU set A in the GDT.  The
; testbench's external master (+xdma_*) writes the descriptor's high dword
; right after the CPU reads it.  A 486 sets A with a locked read-modify-write,
; so the external write is never lost: it lands before the locked read or
; after the locked write.  It writes bytes 7 (base[31:24]=12h) and 5 (access
; B2h, DPL1); both must survive (byte 5 as B2h or B3h).
BITS 32
ORG 0
GDT equ 0x9800
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff        ; 0x08: code, base 0x10000 (current CS)
    mov dword [GDT+12], 0x00cf9a01
    mov dword [GDT+16], 0x0000ffff       ; 0x10: flat data, A=0
    mov dword [GDT+20], 0x00cf9200
    mov word [0x9700], 23
    mov dword [0x9702], GDT
    lgdt [0x9700]
    invd                                  ; descriptor table not in the L1
    mov ax, 0x10
    mov ds, ax                            ; descriptor read + A-bit write
    invd                                  ; see RAM, not a stale line
    mov eax, [es:GDT+20]
    out 0xe4, eax
    mov ebx, eax                          ; external write: base[31:24]=12h,
    shr ebx, 24                           ;   access byte B2h (DPL1, A=0)
    cmp ebx, 0x12
    jne fail
    mov ebx, eax
    shr ebx, 8
    and ebx, 0xfe
    cmp ebx, 0xb2
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
