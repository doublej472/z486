; expand_down_stack - 32-bit and 16-bit expand-down stack segments in protected
; mode (Viper CTR's SGS sound mixer).  An expand-down SS with limit 0 (valid
; 1..FFFFFFFFh, B=1) and a 16-bit one with limit 0FFFh (valid 1000h..FFFFh,
; B=0): PUSH/POP, CALL/RET and a software interrupt through a 32-bit gate must
; all work.  Before the fix every push faulted (#SS -> #DF -> triple fault).
BITS 16
cpu 386
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 9000h
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp dword 08h:protected

BITS 32
protected:
    mov ax, 10h
    mov ds, ax
    mov es, ax

    ; ---- 32-bit expand-down stack, limit 0, B=1
    mov ax, 18h
    mov ss, ax
    mov esp, 60000h
    push dword 12345678h
    cmp dword [ss:esp], 12345678h
    jne fail
    pop eax
    cmp eax, 12345678h
    jne fail
    call probe_call
ret_here:
    cmp esp, 60000h
    jne fail
    int 40h
    cmp dword [ds:ints], 1
    jne fail
    cmp esp, 60000h
    jne fail

    ; ---- 16-bit expand-down stack at 80000h, limit 0FFFh, B=0
    mov ax, 20h
    mov ss, ax
    mov esp, 8000h
    push word 0beefh
    pop bx
    cmp bx, 0beefh
    jne fail
    push dword 0cafef00dh
    pop ebx
    cmp ebx, 0cafef00dh
    jne fail
    int 40h
    cmp dword [ds:ints], 2
    jne fail
    cmp sp, 8000h
    jne fail

    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

probe_call:
    push ebp
    mov ebp, esp
    mov eax, [ss:ebp+4]
    cmp eax, ret_here
    pop ebp
    jne fail
    ret

int_handler:
    inc dword [ds:ints]
    iretd

fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF            ; 08: code 32, base 0x10000, limit 0xFFFFF
    dq 0x00CF93010000FFFF            ; 10: data 32, base 0x10000, limit 0xFFFFF
    dq 0x0040960000000000            ; 18: data, expand-down, B=1, base 0, limit 0
    dq 0x0000960400000FFF            ; 20: data, expand-down, B=0, base 0x80000, limit 0FFFh
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    times 40h dq 0
    dw int_handler                  ; 40h: 32-bit interrupt gate, selector 08
    dw 08h
    db 0, 8eh
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

ints: dd 0
