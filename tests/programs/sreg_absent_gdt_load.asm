; sreg_absent_gdt_load.asm - a protected-mode segment-register load of a
; selector whose GDT descriptor is an all-zero (null / system) descriptor, with
; an IDT that is also all zeros, must not livelock the core.
;
; The authentic PC-9821Xe10 ITF (the second protected-mode block at physical
; 0xF8A1F) does exactly this: its own A20-closed window walk (`out 0x37,9` at
; BANK4@0x8F19 closes the gate, then a `rep stosd` of zeros at ES:0x8000 with
; ES base 0x0010_0000 wraps to physical 0x8000 under the PC-98 1 MiB wrap) wipes
; the GDT image at 0x8000 and the IDT at 0x9000.  The ITF's line printer then
; does `mov ax,0x30 / mov es,ax / mov al,[es:0x3fe0]` at physical 0xF9283 and
; the descriptor the CPU reads from the GDT is all zeros.  The guest's PC is
; then held at that instruction forever.
;
; z486's protection unit returns "no redirect" (a verdict of 0x000) for that
; descriptor -- a system descriptor (S=0) matches no term of TST_DES_SIMPLE --
; so the segment-load routine's own default LJUMP (uc=0x5D1) sends the microcode
; to the exception entry at 0x85D.  No address or protection unit raises a fault
; for that verdict, so the delivery has no fault state; and because the IDT gate
; it then fetches is itself an all-zero (unusable) gate, the gate-type test
; returns "no redirect" too and the microcode's own JMP_GFAULT_INT redirect
; (test constant 0x2A) sends it straight back to the same entry.  The delivery
; re-enters itself every 56 cycles forever instead of escalating: a real 486
; raises #DF while delivering #GP and, when the #DF gate is unusable too, takes
; the triple fault (CPU reset the firmware's POST already knows how to resume
; from).  No memory request is ever presented and the architectural EIP never
; moves.
;
; This payload reproduces that state with no PC-9821 context: valid CS/DS/SS
; descriptors from the testbench, an all-zero GDT entry at selector 0x30 and an
; all-zero IDT, then the ITF's own three instructions.
;
; Result protocol:
;   Port 0xE0: 0x01 = pass, 0xFF = fail
;   Port 0xE4: failure index
;   (the expected outcome is the triple-fault reset asserted by the testbench,
;    so a run that reaches the port write has already failed)

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

; The ITF's own GDTR/IDTR descriptor prefixes, pointing at the memory its walk
; zeroed: GDT limit 0x98 base 0x0000_8000, IDT limit 0x0800 base 0x0000_9000.
align 8
gdt_img:
    times 0x20 dq 0          ; the GDT image the walk left behind: all zeros

gdt_desc:
    dw 0x0098
    dd 0x00008000

idt_desc:
    dw 0x0800
    dd 0x00009000

times 0x200 - ($ - $$) db 0x90

start:
    cli
    lgdt [cs:gdt_desc]       ; GDT base 0x8000, limit 0x98 -- zeros in RAM
    lidt [cs:idt_desc]       ; IDT base 0x9000, limit 0x800 -- zeros in RAM

    mov ax, 0x30             ; selector 0x30 -> GDT entry 6 = all zeros
    mov es, ax               ; must not livelock here
    mov al, [es:0x3fe0]      ; and this read must not be attempted

    ; A core that keeps running reaches here, which is the failure.
    mov eax, 1
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

times 0x400 - ($ - $$) db 0
