; ac_v86_task - #AC on a misaligned stack access in a V86 task entered by a
; task switch (new TSS EFLAGS.VM=1, AC=1)
;
; CR0.AM=1.  JMP to a 386 TSS whose EFLAGS has VM, AC and IOPL=3 starts a
; virtual-8086 task.  Its misaligned word PUSH (SP odd) runs at CPL3 and must
; raise #AC(0) whatever DPL the task switch left in the SS cache; the #AC
; handler (ring 0, ESP0 from the V86 task's TSS) clears AC in the saved
; EFLAGS so the PUSH completes.  Fail (port E4): 0x22xx = #AC count xx after
; the PUSH, 0x44xx = bad #AC error code.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_V86 equ 0x20
STACK0_TOP  equ 0x7000
VM86_SEG    equ 0x1000
VM86_SP     equ 0xE100

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  eax, 0x00040001              ; PE, AM
    mov cr0, eax
    jmp SEL_CODE0:pm16_entry

pm16_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK0_TOP
    mov word [ac_count], 0
    mov ax, SEL_TSS_OLD
    ltr ax
    jmp SEL_TSS_V86:0

vm86_entry:
    mov sp, VM86_SP - 1              ; misaligned V86 stack
    push ax                          ; #AC(0), then completes with AC=0
    mov sp, VM86_SP
    mov ax, 0x2200
    or  ax, [ac_count]
    cmp word [ac_count], 1
    jne v86_fail
    int 0x22                         ; pass
v86_fail:
    int 0x23

ac_handler:
    mov bp, sp
    mov ax, SEL_DATA0
    mov ds, ax
    cmp dword [bp], 0                ; error code 0
    jne .bad
    inc word [ac_count]
    and dword [bp+12], ~0x40000      ; clear AC in the saved EFLAGS
    add sp, 4
    iretd
.bad:
    mov ax, 0x4400
    jmp fail16

pass_handler:
    mov al, 1
    out STATUS_PORT, al
    hlt
fail_handler:
fail16:
    movzx eax, ax
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 8
gdt:
    dq 0
    dw 0xffff, 0x0000                ; 08 ring-0 USE16 code, base 0x10000
    db 0x01, 10011011b, 0, 0
    dw 0xffff, 0x0000                ; 10 ring-0 USE16 data, base 0x10000
    db 0x01, 10010011b, 0, 0
    dw 0x67, tss_old                 ; 18 386 TSS
    db 0x01, 10001001b, 0, 0
    dw 0x67, tss_v86                 ; 20 386 TSS of the V86 task
    db 0x01, 10001001b, 0, 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

%macro GATE 1
    dw %1
    dw SEL_CODE0
    db 0, 11101110b
    dw 0
%endmacro
align 8
idt:
    times 17 dq 0
    GATE ac_handler                  ; 17 #AC
    times (0x22 - 18) dq 0
    GATE pass_handler                ; 22
    GATE fail_handler                ; 23
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss_old:
    times 26 dd 0
align 4
tss_v86:
    dd 0, STACK0_TOP - 0x100, SEL_DATA0, 0, 0, 0, 0   ; 00 link, ESP0, SS0, ...
    dd 0                             ; 1C CR3
    dd vm86_entry                    ; 20 EIP
    dd 0x00063202                    ; 24 EFLAGS: AC, VM, IOPL=3, IF
    dd 0, 0, 0, 0                    ; 28 EAX ECX EDX EBX
    dd VM86_SP                       ; 38 ESP
    dd 0, 0, 0                       ; 3C EBP ESI EDI
    dd VM86_SEG, VM86_SEG, VM86_SEG, VM86_SEG, VM86_SEG, VM86_SEG  ; ES CS SS DS FS GS
    dd 0                             ; 60 LDTR
    dw 0, 0x68

ac_count: dw 0
