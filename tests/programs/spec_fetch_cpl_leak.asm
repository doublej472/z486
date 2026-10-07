; spec_fetch_cpl_leak.asm - speculative branch-target line adopted across a CPL change
;
; Reproducer for the fix that invalidates the speculative fetch context on a CPL
; change ("prefetch: invalidate speculative fetch context on CPL change").
;
; z486's branch-target line buffer is keyed on its linear address only and
; deliberately survives a front-end flush.  Before the fix nothing recorded which
; CPL had validated a buffered line, so a line fetched and adopted at CPL 0 could
; be re-owned by a ring-3 branch to the same linear address -- executing
; supervisor-only (U/S=0) code at ring 3 without the permission check the fetch
; would have taken.  The fix latches the launch CPL (`spec_cpl`) and gates every
; consumer of the buffer, and the paging unit's fetch-side checks, on the live
; architectural CPL.
;
; Flow:
;   1) ring 0: CALL a supervisor-only (U/S=0) code line.  The speculative fetch
;      buffers that line at CPL 0 and the taken call's flush adopts it.  The trap
;      is entered at ring 0, sees CS=RPL0, and returns.
;   2) ring 0: IRET outer-level to ring 3 in a user (U/S=1) code page whose CS
;      base (0x20000) differs from ring 0's (0x10000), so its branch to the same
;      physical trap line uses a wrapped 32-bit displacement.
;   3) ring 3: JMP the trap line.  PRE-FIX `spec_context_ok` does not exist: the
;      buffered CPL-0 line is re-owned and adopted, the queue is seeded from it,
;      and the trap runs at ring 3 (it reads CS, sees the ring-3 RPL, and reports
;      FAIL).  POST-FIX the CPL change invalidated the buffer, the fetch is
;      re-issued at CPL 3, the U/S=0 page gives a protection #PF (error code
;      0x05, CR2=0x10800), and the ring-0 handler reports PASS.
;
; The trap line is 15 bytes so it fits inside the single 16-byte line the buffer
; holds: the leak path never needs a second fetch, so a pre-fix run reports the
; leak instead of faulting on the next line.
;
; Result protocol: port 0xE0 status (0x01 pass, 0xFF fail), port 0xE4 code.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0    equ 0x08
SEL_DATA0    equ 0x10
SEL_CODE3    equ 0x18
SEL_DATA3    equ 0x20
SEL_CODE3_R3 equ (SEL_CODE3 | 3)   ; ring-3 code selector (RPL 3)
SEL_DATA3_R3 equ (SEL_DATA3 | 3)   ; ring-3 data selector (RPL 3)
SEL_TSS      equ 0x28

LEAK_LINE  equ 0x00010800       ; supervisor-only trap line (linear)
RING3_BASE equ 0x00020000       ; user code page (linear == physical)
RING3_ENTRY equ 0x00000000      ; EIP3: RING3_BASE + 0 == linear 0x20000
ESP3_OFF   equ 0x00000800       ; SS3 base 0x30000 -> ring-3 stack at 0x30800
ESP0_START equ 0x0000F000       ; SS0 base 0x10000 -> ring-0 stack at 0x1F000
ESP0_OFF   equ 0x00006000       ; TSS ESP0 offset (SS0 base 0x10000 -> 0x16000)

;==================================================================
; ring-0 #PF handler.  ring3 -> ring0 frame (SS0:ESP0):
;   [esp+00]=err [esp+04]=EIP [esp+08]=CS [esp+0C]=EFLAGS
;   [esp+10]=ESP3 [esp+14]=SS3
;==================================================================
pf_handler:
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, cr2
    and eax, 0xFFFFF000
    cmp eax, LEAK_LINE & 0xFFFFF000
    jne .fail_cr2
    mov eax, [esp]              ; #PF error code
    test al, 4                  ; U/S: the faulting access was a user fetch
    jz .fail_err
    mov al, 0x01
    out STATUS_PORT, al
    hlt

.fail_cr2:
    mov eax, 0x0000C2ED
    out DATA_PORT, eax
    jmp .fail
.fail_err:
    movzx eax, word [esp]
    or eax, 0x0000E000
    out DATA_PORT, eax
.fail:
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

;==================================================================
; ring-0 #GP handler (setup diagnostics).
;==================================================================
gp_handler:
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, [esp]              ; #GP error code
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

;==================================================================
; GDT
;==================================================================
align 8
gdt:
    dq 0x0000000000000000       ; 0x00 null
    dq 0x00CF9B010000FFFF       ; 0x08 ring-0 code, base 0x00010000
    dq 0x00CF93010000FFFF       ; 0x10 ring-0 data, base 0x00010000
    dq 0x00CFFA020000FFFF       ; 0x18 ring-3 code, base 0x00020000, DPL3
    dq 0x00CFF2030000FFFF       ; 0x20 ring-3 data, base 0x00030000, DPL3
tss_desc:
    dw 0x0067
    dw tss
    db 0x01
    db 0x89
    db 0x00
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

;==================================================================
; IDT: vector 0x0E = #PF, vector 0x0D = #GP (386 interrupt gates)
;==================================================================
align 8
idt:
    times 0x0D dq 0
    dw gp_handler               ; 0x0D #GP
    dw SEL_CODE0
    db 0
    db 0x8E
    dw 0
    dw pf_handler               ; 0x0E #PF
    dw SEL_CODE0
    db 0
    db 0x8E
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

;==================================================================
; 386 TSS (SS0/ESP0 for the ring3 -> ring0 fault stack switch)
;==================================================================
align 4
tss:
    dd 0                        ; +00 backlink
    dd ESP0_OFF                 ; +04 ESP0
    dd SEL_DATA0                ; +08 SS0
    times 23 dd 0
tss_end:

;==================================================================
; ring-0 entry (EIP=0x200); the harness starts execution here.
;==================================================================
times 0x200 - ($ - $$) db 0x90
start:
    cli
    ; DS is already 0x0010 with base 0x10000 from the harness segment cache;
    ; load GDTR/IDTR from it before any selector is reloaded through the GDT.
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, ESP0_START
    mov ax, SEL_TSS
    ltr ax

    ; The harness builds the page directory with its own U/S=0; an x86 user
    ; access also needs the PDE's U bit.  Linear 0x40000 aliases physical 0
    ; (the page directory) in the JSON's page_tables, so patch PDE[0].U and
    ; reload CR3 (the write also drops any stale TLB entry).
    or dword [0x00030000], 0x04
    mov eax, cr3
    mov cr3, eax

    ; (1) buffer + adopt the supervisor trap line at CPL 0.  The CALL's taken
    ; flush seeds the queue from the speculatively fetched line.
    call leak_line

    ; let a pre-fix in-flight spec fetch settle before the privilege change
    times 16 nop

    ; (2) outer-level IRET to ring 3
    push dword SEL_DATA3_R3
    push dword ESP3_OFF
    push dword 0x00003002       ; EFLAGS: IOPL=3 (ring-3 may OUT), IF=0
    push dword SEL_CODE3_R3
    push dword RING3_ENTRY
    iretd

    hlt

;==================================================================
; The supervisor-only trap line.  Also the speculative fetch target.
;==================================================================
times 0x800 - ($ - $$) db 0x90
leak_line:
    mov ax, cs
    cmp ax, SEL_CODE3_R3
    jne .ref_ok
    mov al, 0xFF
    out STATUS_PORT, al         ; LEAK: ring 3 executed this supervisor line
    hlt
.ref_ok:
    ret                         ; ring 0: benign reference execution

;==================================================================
; ring-3 user code page (file offset 0x10000 -> physical 0x20000,
; linear 0x20000 with CS3 base 0x20000; the PTE carries U/S=1).
;==================================================================
times 0x10000 - ($ - $$) db 0x90
ring3_start:
    db 0xE9                     ; JMP rel32 to linear 0x10800.  CS3 base is
    dd 0xFFFF0800 - 5           ; 0x20000, so the target EIP is 0xFFFF0800.
    hlt
