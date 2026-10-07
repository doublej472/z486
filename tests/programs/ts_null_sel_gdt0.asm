; ts_null_sel_gdt0 - a task switch that loads null selectors (FS/GS = 0 in
; the new TSS) must not write the GDT[0] slot
;
; A 486 never touches GDT[0]; the 386 CROM word 7E6 wrote the dword just read
; back to GDT[0]+4 (removed by 5262bc4).  The rewrite stores an unchanged
; value, so it is made visible with paging: the GDT starts at linear 0x5FF8,
; its null slot is the last 8 bytes of a read-only page (CR0.WP=1) and every
; real descriptor lies on the next, writable page.  Any write to GDT[0]
; raises #PF (fail: port 0xE4 = 0xBAD00000 | error code, then CR2).
BITS 32
ORG 0
GDT     equ 0x5FF8                   ; GDT[0] on the read-only page 0x5000
IDT     equ 0x8000
TSS_OLD equ 0x7000
TSS_NEW equ 0x7100
SEL_CODE equ 0x08
SEL_DATA equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_NEW equ 0x20
start:
    mov esp, 0x9000
    ; GDT[1..4] at 0x6000 (writable page)
    mov dword [GDT+8], 0x0000ffff        ; 08: code, base 0x10000
    mov dword [GDT+12], 0x00cf9b01
    mov dword [GDT+16], 0x0000ffff       ; 10: flat data
    mov dword [GDT+20], 0x00cf9300
    mov dword [GDT+24], (TSS_OLD << 16) | 0x67   ; 18: 386 TSS, available
    mov dword [GDT+28], 0x00008900
    mov dword [GDT+32], (TSS_NEW << 16) | 0x67   ; 20: 386 TSS, available
    mov dword [GDT+36], 0x00008900
    mov word [0xA000], 39
    mov dword [0xA002], GDT
    lgdt [0xA000]
    mov eax, pf_handler
    mov word [IDT+14*8+0], ax
    mov word [IDT+14*8+2], SEL_CODE
    mov word [IDT+14*8+4], 0x8e00
    shr eax, 16
    mov word [IDT+14*8+6], ax
    mov word [0xA010], 0x7ff
    mov dword [0xA012], IDT
    lidt [0xA010]
    jmp SEL_CODE:.cs
.cs:
    mov ax, SEL_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    ; new TSS: CS/SS/DS/ES valid, FS/GS/LDTR null
    mov edi, TSS_NEW
    xor eax, eax
    mov ecx, 26
    rep stosd
    mov eax, cr3
    mov [TSS_NEW+0x1C], eax
    mov dword [TSS_NEW+0x20], task_entry
    mov dword [TSS_NEW+0x24], 0x2
    mov dword [TSS_NEW+0x38], 0x9800
    mov dword [TSS_NEW+0x48], SEL_DATA
    mov dword [TSS_NEW+0x4C], SEL_CODE
    mov dword [TSS_NEW+0x50], SEL_DATA
    mov dword [TSS_NEW+0x54], SEL_DATA
    mov word [TSS_NEW+0x66], 0x68
    mov ax, SEL_TSS_OLD
    ltr ax
    jmp SEL_TSS_NEW:0
    mov eax, 0x10
    jmp fail

task_entry:
    mov ax, fs
    or ax, ax
    jnz fail
    mov al, 1
    out 0xe0, al
    hlt

pf_handler:
    pop eax
    or eax, 0xBAD00000
    out 0xe4, eax
    mov eax, cr2
    out 0xe4, eax
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
