; seg_limit_back_to_back.asm - back-to-back memory ops close to a segment limit.
;
; A memory operand's limit verdict is a property of that access, but the check
; is combinational on the presented word / IND / segment cache. When a second
; access is already resident while the first is still being serviced, the first
; access' word and IND are what the checker sees, and the second access' word
; must not be judged by them.  ES has limit 0x1F and each pair below keeps both
; operands inside the limit, with the younger one ending exactly at 0x1F:
;
;   load/load   - a slow load of ES:0x10, then a byte read at ES:0x1F
;   store/load  - a store to ES:0x00, then a byte read at ES:0x1F
;   load/store  - a slow load of ES:0x10, a store to ES:0x00, then ES:0x1F
;
; The genuine-fault control is a byte read at ES:0x20 (0x20 > limit): it must
; #GP.  A spurious fault on any pair lands in gp_unexpected and fails the test.
;
; Result protocol:
;   Port 0xE0: 0x01 = pass, 0xFF = fail
;   Port 0xE4: failure word = (check << 8) | markers
;              marker bits: 0 LL, 1 SL, 2 LS, 3 FAULT, 4 OTHER
;              check: 1 load/load did not complete, 2 store/load did not
;                     complete, 3 load/store did not complete, 4 the limit
;                     control did not fault, 5 unexpected fault

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

; DS base is 0x00040000, so these are physical 0x00040Fxx.
MARK_LL    equ 0x00000F00
MARK_SL    equ 0x00000F04
MARK_LS    equ 0x00000F08
MARK_FAULT equ 0x00000F0C
MARK_OTHER equ 0x00000F10

; #GP handler.  Only the genuine limit control (ES:0x20) may fault; any other
; faulting EIP is a spurious #GP and is reported as such.
gp_handler:
    mov eax, [ss:esp]           ; error code
    mov edx, [ss:esp+4]         ; faulting EIP
    add esp, 4                  ; drop the error code
    test eax, eax
    jnz gp_unexpected
    cmp edx, fault_probe
    je gp_fault
gp_unexpected:
    mov dword [ds:MARK_OTHER], 1
    mov dword [ss:esp], unexpected_trap
    iretd
gp_fault:
    mov dword [ds:MARK_FAULT], 1
    mov dword [ss:esp], fault_after
    iretd

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff    ; 0x08: code,  base 0x00010000, limit 0xFFFFF
    dq 0x00cf93040000ffff    ; 0x10: data,  base 0x00040000, limit 0xFFFFF
    dq 0x00cf93030000ffff    ; 0x18: stack, base 0x00030000, limit 0xFFFFF
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

align 8
idt:
    times 13 dq 0
    dw gp_handler
    dw 0x0008
    db 0
    db 0x8e
    dw 0
    times 2 dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd 0x00010000 + idt

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov esp, 0x00000F00

    mov dword [ds:MARK_LL], 0
    mov dword [ds:MARK_SL], 0
    mov dword [ds:MARK_LS], 0
    mov dword [ds:MARK_FAULT], 0
    mov dword [ds:MARK_OTHER], 0

    ; load/load: the cold VIPT load of ES:0x10 is still in flight when the
    ; byte read at ES:0x1F is resident behind it.
    mov ebx, 0x10
    mov eax, [es:ebx]           ; slow VIPT load miss
    mov al, byte [es:ebx+0x0F]  ; last byte at the limit: must not fault
ll_after:
    mov dword [ds:MARK_LL], 1

    ; store/load: a posted store close to the limit, then a byte at the limit.
    mov ebx, 0
    mov dword [es:ebx], 0x11223344
    mov al, byte [es:0x1F]      ; must not fault
sl_after:
    mov dword [ds:MARK_SL], 1

    ; load/store: load, store and a third access all near the limit.
    mov ebx, 0x10
    mov eax, [es:ebx]
    mov dword [es:0], eax
    mov al, byte [es:0x1F]      ; must not fault
ls_after:
    mov dword [ds:MARK_LS], 1

    ; Genuine limit control: 0x20 > limit 0x1F, so this one must #GP.
    mov ebx, 0x20
fault_probe:
    mov al, byte [es:ebx]
fault_after:
    ; Expected: LL=1, SL=1, LS=1, FAULT=1, OTHER=0.
    mov eax, [ds:MARK_LL]
    test eax, eax
    jz fail_ll
    mov eax, [ds:MARK_SL]
    test eax, eax
    jz fail_sl
    mov eax, [ds:MARK_LS]
    test eax, eax
    jz fail_ls
    mov eax, [ds:MARK_FAULT]
    test eax, eax
    jz fail_fault
    mov eax, [ds:MARK_OTHER]
    test eax, eax
    jnz fail_other

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

unexpected_trap:
    mov eax, 5
    jmp fail
fail_ll:
    mov eax, 1
    jmp fail
fail_sl:
    mov eax, 2
    jmp fail
fail_ls:
    mov eax, 3
    jmp fail
fail_fault:
    mov eax, 4
    jmp fail
fail_other:
    mov eax, 5

fail:
    shl eax, 8
    mov edx, [ds:MARK_LL]
    or eax, edx
    mov edx, [ds:MARK_SL]
    shl edx, 1
    or eax, edx
    mov edx, [ds:MARK_LS]
    shl edx, 2
    or eax, edx
    mov edx, [ds:MARK_FAULT]
    shl edx, 3
    or eax, edx
    mov edx, [ds:MARK_OTHER]
    shl edx, 4
    or eax, edx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

times 0x800 - ($ - $$) db 0
