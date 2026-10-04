; seg_limit_edge.asm - boundary arithmetic of the segmented memory model:
;   * a dword at offset 0xFFFFFFFF in a max-limit (G=1, limit 0xFFFFF) segment
;     must #GP on the size crossing, while a byte there must not fault;
;   * a write to a read-only data segment must #GP (write_fault);
;   * a G=1 segment (limit field 0x0FFF -> byte limit 0xFFFFF) must admit a byte
;     at 0xFFFFF and fault a byte at 0x100000.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

CODE_LINEAR equ 0x00010000

MARK_WB    equ 0x5000    ; wrap byte faulted     (want 0)
MARK_WD    equ 0x5004    ; wrap dword faulted    (want 1)
MARK_RO    equ 0x5008    ; read-only write       (want 1)
MARK_GOK   equ 0x500C    ; G=1 byte at 0xFFFFF   (want 0)
MARK_GB    equ 0x5010    ; G=1 byte at 0x100000  (want 1)
MARK_OTHER equ 0x5014    ; stray fault           (want 0)

align 8
gdt:
    dq 0                        ; 0x00 null
    dq 0x00CF9B010000FFFF       ; 0x08 code, base 0x10000, limit 0xFFFFF (G=1)
    dq 0x00CF93000000FFFF       ; 0x10 DS flat writable, limit max
    dq 0x00CF93000000FFFF       ; 0x18 ES flat writable, limit max (wrap probe)
    dq 0x00CF91040000FFFF       ; 0x20 FS read-only data (W=0), base 0x40000
    dq 0x00C09300000000FF       ; 0x28 GS G=1 limit 0xFF -> byte limit 0xFFFFF
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_LINEAR + gdt

; #GP handler. Each probe has a known faulting EIP; record which one faulted and
; resume after it. A fault on a must-not-fault probe is recorded too.
gp_handler:
    mov eax, [ss:esp]           ; error code
    mov edx, [ss:esp + 4]       ; faulting EIP
    add esp, 4                  ; drop error code so [esp] is the EIP slot
    cmp edx, probe_wrap_dword
    je  .wrap_dword
    cmp edx, probe_ro_write
    je  .ro_write
    cmp edx, probe_g_boundary
    je  .g_boundary
    cmp edx, probe_wrap_byte
    je  .wrap_byte
    cmp edx, probe_g_ok
    je  .g_ok
    mov dword [ds:MARK_OTHER], 1        ; stray fault
    mov dword [ss:esp], unexpected_after
    iretd
.wrap_dword:
    mov dword [ds:MARK_WD], 1
    mov dword [ss:esp], wrap_dword_after
    iretd
.ro_write:
    mov dword [ds:MARK_RO], 1
    mov dword [ss:esp], ro_write_after
    iretd
.g_boundary:
    mov dword [ds:MARK_GB], 1
    mov dword [ss:esp], g_boundary_after
    iretd
.wrap_byte:
    mov dword [ds:MARK_WB], 1
    mov dword [ss:esp], wrap_byte_after
    iretd
.g_ok:
    mov dword [ds:MARK_GOK], 1
    mov dword [ss:esp], g_ok_after
    iretd

align 8
idt:
    times 13 dq 0           ; vectors 0..12 absent
    dw gp_handler           ; vector 13: #GP
    dw 0x0008
    db 0
    db 0x8e                 ; present DPL0 386 interrupt gate
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_LINEAR + idt

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov esp, 0x3F00

    mov dword [ds:MARK_WB], 0
    mov dword [ds:MARK_WD], 0
    mov dword [ds:MARK_RO], 0
    mov dword [ds:MARK_GOK], 0
    mov dword [ds:MARK_GB], 0
    mov dword [ds:MARK_OTHER], 0

;--- gap 1: offset wrap at the top of a max-limit segment
    mov ax, 0x18
    mov es, ax
    xor eax, eax
probe_wrap_byte:
    mov al, [es:0xFFFFFFFF]     ; byte at the last offset -> must NOT fault
wrap_byte_after:
probe_wrap_dword:
    mov eax, [es:0xFFFFFFFF]    ; dword wraps past 0xFFFFFFFF -> must #GP
wrap_dword_after:

;--- gap 3: write to a read-only data segment
    mov ax, 0x20
    mov fs, ax
    xor eax, eax
probe_ro_write:
    mov dword [fs:0x1000], 0x12345678    ; must #GP (write_fault)
ro_write_after:

;--- gap 4: G=1 limit boundary (byte limit 0xFFFFF)
    mov ax, 0x28
    mov gs, ax
    xor eax, eax
probe_g_ok:
    mov al, [gs:0xFFFFF]        ; last byte of the byte limit -> must NOT fault
g_ok_after:
probe_g_boundary:
    mov al, [gs:0x100000]       ; one past the byte limit -> must #GP
g_boundary_after:
unexpected_after:

    mov eax, [ds:MARK_WB]
    test eax, eax
    jnz fail_wb
    mov eax, [ds:MARK_WD]
    test eax, eax
    jz  fail_wd
    mov eax, [ds:MARK_RO]
    test eax, eax
    jz  fail_ro
    mov eax, [ds:MARK_GOK]
    test eax, eax
    jnz fail_gok
    mov eax, [ds:MARK_GB]
    test eax, eax
    jz  fail_gb
    mov eax, [ds:MARK_OTHER]
    test eax, eax
    jnz fail_other

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_wb:
    mov eax, 1
    jmp fail
fail_wd:
    mov eax, 2
    jmp fail
fail_ro:
    mov eax, 3
    jmp fail
fail_gok:
    mov eax, 4
    jmp fail
fail_gb:
    mov eax, 5
    jmp fail
fail_other:
    mov eax, 6

fail:
    mov edx, eax
    mov eax, [ds:MARK_WB]
    or  eax, edx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

times 0x800 - ($ - $$) db 0
