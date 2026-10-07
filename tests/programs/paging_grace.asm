; paging_grace - after MOV CR0 sets PG, instruction fetches stay untranslated
; until the next branch (the 486 prefetch queue).  EMM386's switch page is not
; identity-mapped, so the instruction behind MOV CR0 must come from the page it
; was prefetched from.  The translated view of the code page is a trap page, so
; a core that translates the queued instruction immediately lands in the trap.
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

start:
    cli
    mov esp, 0x00008000

    ; Trap page: the translated view of linear 0x10000 maps to physical 0x30000.
    ; If the instruction after MOV CR0 is fetched translated, it lands here.
    mov byte [0x30000 + B], 0xeb         ; jmp $
    mov byte [0x30000 + B + 1], 0xfe

    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

B:
    mov ebx, 0x1111                      ; prefetched before PG: must run
    mov eax, 0x10000 + C                 ; linear 0x20000+C -> physical 0x10000+C
    jmp eax                              ; branch: fetch is translated now

C:
    cmp ebx, 0x1111
    jne fail
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail:
    mov al, 0xff
    mov dx, STATUS_PORT
    out dx, al
    hlt

