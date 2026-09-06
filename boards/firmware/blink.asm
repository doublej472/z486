bits 16
org 0

%ifndef BLINK_DELAY
%define BLINK_DELAY 1000000
%endif

LED_PORT equ 0x0080

start:
    cli
    cld
    mov dx, LED_PORT
    mov al, 0x55

.next_pattern:
    out dx, al
    xor al, 0xff
    mov ecx, BLINK_DELAY

.delay:
    dec ecx
    jnz .delay
    jmp .next_pattern

; The architectural reset fetch is at physical 0xfffffff0. The demo ROM is
; also aliased at 0x000f0000, so enter the ordinary real-mode BIOS segment.
times 0xfff0 - ($ - $$) db 0xff
reset_vector:
    jmp 0xf000:0x0000

times 0x10000 - ($ - $$) db 0xff
