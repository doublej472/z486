; seg_limit_dcache_miss.asm - a limit-violating data access must #GP whether or
; not it hits the data cache.
;
; z486 evaluates the segmentation limit/protection verdict behind `check_en`
; (= mem_op_eligible).  A direct (VIPT) load raises `vipt_load_exec_block`
; itself (vipt_load_busy, which is asserted for a cache hit exactly as for a
; miss) for the whole bus-op window, so gating the check on that term disables
; it on exactly the cycles it has to run on and the load commits instead of
; faulting -- hit or miss.  A real PC-9821Xe10 ITF's POST tests this contract
; itself: BANK4@0xF86F2 does `mov ax, word ptr es:[bx]` with ES = {limit 0, base
; 0x00010000} and bx = 0 (a word access at offset 0 of a limit-0 segment); it then
; waits for its own "a fault was delivered" flag and prints PROTECTED MODE ERROR
; when the fault never arrives.
;
; This payload isolates the core behaviour with no platform context at all.  DS
; and the violating ES share a base, so the same linear address is reachable
; through a valid descriptor (a read that must NOT fault) and through a limit-0
; one:
;
;   hot     - word read at offset 0 of a line already in the D-cache
;   cold    - word read at offset 0 of an untouched line, i.e. a D-cache miss
;   byte0   - byte read at offset 0 through the limit-0 descriptor: 0 <= limit,
;             so no fault is allowed.  This is the control that the fault comes
;             from the operand's end offset and not from the descriptor's
;             identity.
;   byte1   - byte read at offset 1 through the same descriptor: 1 > limit, so
;             it must fault.  Together with byte0 this pins that the check is
;             still end-offset sensitive rather than "fault everything".
;
; Each probe has its own #GP continuation and marks whether the fault arrived,
; so one failing run shows the whole pattern (hot vs cold, byte0 vs byte1)
; instead of a bare "failed".
;
; Result protocol:
;   Port 0xE0: 0x01 = pass, 0xFF = fail
;   Port 0xE4: failure word = (check << 8) | markers
;              marker bits: 0 HOT, 1 COLD, 2 BYTE0, 3 BYTE1, 4 OTHER
;                           (1 = a #GP was delivered)
;              check: 1 hot did not fault, 2 cold did not fault,
;                     3 byte0 control faulted, 4 byte1 did not fault,
;                     5 unexpected fault

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

; DS and the violating ES share this base, so both reach the same linear address.
BASE       equ 0x00040000
HOT_OFF    equ 0x00000000
COLD_OFF   equ 0x00008000

MARK_HOT   equ 0x00000F00
MARK_COLD  equ 0x00000F04
MARK_BYTE0 equ 0x00000F08
MARK_BYTE1 equ 0x00000F0C
MARK_OTHER equ 0x00000F10

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff    ; 0x08: code,  base 0x00010000, limit 0xFFFFF
    dq 0x00cf93040000ffff    ; 0x10: data,  base 0x00040000, limit 0xFFFFF
    dq 0x00cf93030000ffff    ; 0x18: stack, base 0x00030000, limit 0xFFFFF
    dq 0x00cf93040000ffff    ; 0x20: data alias of 0x10
    dq 0x0000930400000000    ; 0x28: data,  base 0x00040000, LIMIT 0  <- violating
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

; #GP handler.  Every probe is a segment-limit violation, so the 486 pushes an
; error code of 0; anything else is a different bug and is reported as such.
gp_handler:
    mov eax, [ss:esp]           ; error code
    mov edx, [ss:esp+4]         ; faulting EIP
    add esp, 4                  ; drop the error code
    test eax, eax
    jnz gp_unexpected
    cmp edx, hot_word
    je gp_hot
    cmp edx, cold_word
    je gp_cold
    cmp edx, byte0_probe
    je gp_byte0
    cmp edx, byte1_probe
    je gp_byte1
gp_unexpected:
    mov dword [ds:MARK_OTHER], 1
    mov dword [ss:esp], unexpected_fault
    iretd
gp_hot:
    mov dword [ds:MARK_HOT], 1
    mov dword [ss:esp], hot_after
    iretd
gp_cold:
    mov dword [ds:MARK_COLD], 1
    mov dword [ss:esp], cold_after
    iretd
gp_byte0:
    mov dword [ds:MARK_BYTE0], 1
    mov dword [ss:esp], byte0_after
    iretd
gp_byte1:
    mov dword [ds:MARK_BYTE1], 1
    mov dword [ss:esp], byte1_after
    iretd

; Only vector 13 is present.  Any other exception therefore raises #GP, whose
; error code is the offending vector's IDT index, and gp_unexpected reports it.
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
    xor ebx, ebx

    mov dword [ds:MARK_HOT], 0
    mov dword [ds:MARK_COLD], 0
    mov dword [ds:MARK_BYTE0], 0
    mov dword [ds:MARK_BYTE1], 0
    mov dword [ds:MARK_OTHER], 0

    ; Prime the D-cache line at HOT_OFF through the valid DS descriptor: this
    ; read must not fault, and it makes the first violating read of that line a
    ; cache hit.
    mov eax, [ds:ebx]

    mov eax, 0x28               ; base 0x00040000, limit 0
    mov es, ax

hot_word:
    mov ax, word [es:ebx]       ; linear BASE+HOT_OFF, D-cache hit
hot_after:
    mov ebx, COLD_OFF
cold_word:
    mov ax, word [es:ebx]       ; linear BASE+COLD_OFF, D-cache miss
cold_after:
    xor ebx, ebx
byte0_probe:
    mov al, byte [es:ebx]       ; 0 <= limit, so no fault is allowed
byte0_after:
    mov ebx, 1
byte1_probe:
    mov al, byte [es:ebx]       ; 1 > limit, so this one must fault
byte1_after:
    xor ebx, ebx

    ; Expected markers: HOT=1, COLD=1, BYTE0=0, BYTE1=1, OTHER=0.
    mov eax, [ds:MARK_COLD]
    test eax, eax
    jz fail_cold
    mov eax, [ds:MARK_HOT]
    test eax, eax
    jz fail_hot
    mov eax, [ds:MARK_BYTE0]
    test eax, eax
    jnz fail_byte0
    mov eax, [ds:MARK_BYTE1]
    test eax, eax
    jz fail_byte1
    mov eax, [ds:MARK_OTHER]
    test eax, eax
    jnz fail_other

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

unexpected_fault:
    mov eax, 5
    jmp fail

fail_hot:
    mov eax, 1
    jmp fail
fail_cold:
    mov eax, 2
    jmp fail
fail_byte0:
    mov eax, 3
    jmp fail
fail_byte1:
    mov eax, 4
    jmp fail
fail_other:
    mov eax, 5

fail:
    shl eax, 8
    mov edx, [ds:MARK_HOT]
    or eax, edx
    mov edx, [ds:MARK_COLD]
    shl edx, 1
    or eax, edx
    mov edx, [ds:MARK_BYTE0]
    shl edx, 2
    or eax, edx
    mov edx, [ds:MARK_BYTE1]
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
