; desc_ro_gdt - segment loads must not write a descriptor whose A bit
; is already set, nor the null descriptor
;
; The GDT sits in a read-only page and CR0.WP=1, so any supervisor write to it
; raises #PF.  A 486 writes a descriptor only to set a clear A bit (and the
; TSS busy bit), so loading DS/ES from accessed descriptors, FS/GS with a
; null selector, and LDTR (a system descriptor, which has no A bit) must not
; fault.  EBX numbers the step; the #PF handler reports
; it with CR2.
BITS 32
ORG 0
GDT_RW  equ 0x20800          ; RW alias of the GDT page (linear 0x9800)
GDT     equ 0x9800
IDT     equ 0xB000
start:
    mov esp, 0x8000
    mov dword [GDT_RW+0], 0x11112222     ; null descriptor holds a sentinel
    mov dword [GDT_RW+4], 0x33334444
    mov dword [GDT_RW+8], 0x0000ffff     ; 0x08: code, base 0x10000, A=1
    mov dword [GDT_RW+12], 0x00cf9b01
    mov dword [GDT_RW+16], 0x0000ffff    ; 0x10: flat data, A=1
    mov dword [GDT_RW+20], 0x00cf9300
    mov dword [GDT_RW+24], 0xA800000f    ; 0x18: LDT, base 0xA800, limit 0Fh
    mov dword [GDT_RW+28], 0x00008200
    mov word [0xA000], 31
    mov dword [0xA002], GDT
    lgdt [0xA000]
    mov eax, pf_handler                  ; IDT[14] -> pf_handler
    mov word [IDT+14*8+0], ax
    mov word [IDT+14*8+2], 0x08
    mov word [IDT+14*8+4], 0x8e00
    shr eax, 16
    mov word [IDT+14*8+6], ax
    mov word [0xA010], 0x7ff
    mov dword [0xA012], IDT
    lidt [0xA010]
    mov ebx, 1
    mov ax, 0x10
    mov ds, ax                           ; accessed descriptor: no write
    mov ebx, 2
    mov es, ax
    mov ebx, 3
    jmp 0x08:next                        ; accessed code descriptor: no write
next:
    mov ebx, 4
    xor eax, eax
    mov fs, ax                           ; null selector: no descriptor access
    mov ebx, 5
    mov gs, ax
    mov ebx, 6
    mov ax, 0x18
    lldt ax                              ; LDT descriptor: no write
    mov ebx, 7
    cmp dword [GDT+0], 0x11112222
    jne fail
    cmp dword [GDT+4], 0x33334444
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
pf_handler:
    mov eax, cr2
    out 0xe4, eax
    mov eax, ebx
    out 0xe4, eax
fail:
    mov eax, ebx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
