; seg_limit_vipt_boundary.asm - a limit check must not fire on a stale word
; while a direct (VIPT) load owns the ROM window.
;
; The segmentation enable `seg_check_en` may only extend past mem_op_eligible on
; the cycles of a direct load's bus-op window (vipt_load_exec_block), where
; uc_exec is blocked and IND / mem_seg_sel / the resident word all still belong
; to that load.  On the cycles the ROM holds some *other* instruction's word --
; a predecessor's delay/shadow word, or a word whose access is already in
; flight -- the presented IND can differ from the access that word performed, so
; running the checker there would fault an access that has already completed
; correctly.
;
; ES and DS share base 0x40000; DS has a large limit, ES has limit 0x1F, so the
; same line is reachable both through the validity control and through the
; near-limit segment.  Each probe is a direct (VIPT) load followed by a byte
; access whose last byte is exactly at the limit (0x1F) and must NOT fault:
;
;   hit   - prime the line through DS, then a VIPT load of ES:0x10 (D-cache hit)
;           followed by ES:0x1F.
;   miss  - a VIPT load of a cold line, ES:0x40, followed by ES:0x40.
;   jcc   - a not-taken Jcc immediately before a VIPT load (its shadow word
;           stays resident), followed by ES:0x1F.
;
; The genuine-fault control is a byte read at ES:0x20 (0x20 > limit): it must
; #GP.  A spurious fault on any probe lands in gp_unexpected and fails the test.
;
; Result protocol:
;   Port 0xE0: 0x01 = pass, 0xFF = fail
;   Port 0xE4: failure word = (check << 8) | markers
;              marker bits: 0 HIT, 1 MISS, 2 JCC, 3 FAULT, 4 OTHER
;              check: 1 hit probe did not complete, 2 miss probe did not
;                     complete, 3 jcc probe did not complete, 4 the limit
;                     control did not fault, 5 unexpected fault

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

; DS base is 0x00040000, so these are physical 0x00040Fxx.
MARK_HIT   equ 0x00000F00
MARK_MISS  equ 0x00000F04
MARK_JCC   equ 0x00000F08
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
    mov ebx, 0

    mov dword [ds:MARK_HIT], 0
    mov dword [ds:MARK_MISS], 0
    mov dword [ds:MARK_JCC], 0
    mov dword [ds:MARK_FAULT], 0
    mov dword [ds:MARK_OTHER], 0

    ; hit: fill the line through the valid DS alias, then load ES:0x10 directly.
    mov ebx, 0x10
    mov eax, [ds:ebx]
    mov eax, [es:ebx]           ; VIPT load, D-cache hit
    mov al, byte [es:ebx+0x0F]  ; last byte at the limit: must not fault
hit_after:
    mov dword [ds:MARK_HIT], 1

    ; miss: cold 16-byte line at ES:0x00, the VIPT load hands off to paging.
    mov ebx, 0
    mov eax, [es:ebx]           ; VIPT load, D-cache miss
    mov al, byte [es:ebx]       ; must not fault
miss_after:
    mov dword [ds:MARK_MISS], 1

    ; jcc: the not-taken Jcc's ROM shadow word stays resident under the load.
    mov ebx, 0x10
    xor eax, eax
    jnz jcc_taken
    mov eax, [es:ebx]           ; VIPT load in the Jcc reclaim slot
    mov al, byte [es:ebx+0x0F]  ; must not fault
jcc_after:
    mov dword [ds:MARK_JCC], 1
    jmp after_probes
jcc_taken:
    mov dword [ds:MARK_OTHER], 1
    jmp fail

after_probes:
    ; Genuine limit control: 0x20 > limit 0x1F, so this one must #GP.
    mov ebx, 0x20
fault_probe:
    mov al, byte [es:ebx]
fault_after:
    ; Expected: HIT=1, MISS=1, JCC=1, FAULT=1, OTHER=0.
    mov eax, [ds:MARK_HIT]
    test eax, eax
    jz fail_hit
    mov eax, [ds:MARK_MISS]
    test eax, eax
    jz fail_miss
    mov eax, [ds:MARK_JCC]
    test eax, eax
    jz fail_jcc
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
fail_hit:
    mov eax, 1
    jmp fail
fail_miss:
    mov eax, 2
    jmp fail
fail_jcc:
    mov eax, 3
    jmp fail
fail_fault:
    mov eax, 4
    jmp fail
fail_other:
    mov eax, 5

fail:
    shl eax, 8
    mov edx, [ds:MARK_HIT]
    or eax, edx
    mov edx, [ds:MARK_MISS]
    shl edx, 1
    or eax, edx
    mov edx, [ds:MARK_JCC]
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
