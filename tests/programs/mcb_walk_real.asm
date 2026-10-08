; mcb_walk_real.asm - PC-98 DIAGNOSTIC (re-vendor regression guard).
;
; The DOS allocator's exact real-mode MCB-chain walk, from the owner's
; MSDOS.SYS (../round-docs/oom-testplan-REPORT.md section 4). Touhou 5's OOM is
; `mov word [9ECh],5208h` -> `mov bx,[9ECh]` -> INT 21h AH=48h -> this walk.
; This program writes a three-block fake MCB chain into RAM and walks it with
; the kernel's own instruction forms:
;   lodsb/lodsw over the MCB            (string-op load of marker/owner/size)
;   cmp cx,dx / jna                     (the largest-free-so-far accumulator)
;   cmp bx,cx / ja                      (the fit compare, BX = 5208h request)
;   mov ax,ds / add ax,[0x3] / inc ax   (the chain step)
;   mov [si],ax / mov [si+2],bx         (the caller-visible frame store)
; and asserts the computed largest free block equals the hand-derived value.
;
; Expected values are ARITHMETIC over the chain THIS program writes (marker/
; owner/size fields), NOT derived from this core:
;   MCB A: 'M', owned 0x1234, size 2         -> next segment 0x2003
;   MCB B: 'M', free,       size 5           -> next segment 0x2009
;   MCB C: 'M', free,       size 0x5208      -> next segment 0x7212
;   MCB D: 'Z', free,       size 0x300       (last)
;   free sizes = {5, 0x5208, 0x300}; largest = 0x5208; blocks fitting a 0x5208
;   request = {0x5208} -> fit count = 1.
;
; Port 0xE0: 0x01 = pass, 0xFF = fail. Port 0xE4 = failing case number.
;
; NOT in the upstream fork: this is a PC-98 diagnostic. If it proves a bug,
; push it upstream to the upstream CPU tree.

BITS 16
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

MCB_SEG    equ 0x2000        ; first MCB at linear 0x20000
REQ        equ 0x5208        ; Touhou 5's paragraph request
ERR_NOMEM  equ 8             ; DOS "insufficient memory" (symbolic)

; Fixed zero-segment scratch (SS = DS = 0).
FRAME    equ 0x0400          ; frame store: [FRAME]=AX, [FRAME+2]=BX
M_MARKER equ 0x0404          ; last marker byte read
M_OWNER  equ 0x0406          ; last owner word read
M_FITS   equ 0x0408          ; count of free blocks that fit the request

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ds, ax

    ; ---- build the fake MCB chain (one segment per block) -----------------
    mov ax, 0x2000
    mov es, ax
    mov byte [es:0], 'M'
    mov word [es:1], 0x1234
    mov word [es:3], 2

    mov ax, 0x2003
    mov es, ax
    mov byte [es:0], 'M'
    mov word [es:1], 0
    mov word [es:3], 5

    mov ax, 0x2009
    mov es, ax
    mov byte [es:0], 'M'
    mov word [es:1], 0
    mov word [es:3], REQ

    mov ax, 0x7212
    mov es, ax
    mov byte [es:0], 'Z'
    mov word [es:1], 0
    mov word [es:3], 0x300

    ; ---- walk (DS stays 0 for scratch, ES = current MCB segment) ----------
    mov word [M_FITS], 0
    mov ax, MCB_SEG
    mov es, ax              ; ES = first MCB segment
    xor dx, dx              ; DX = largest-free accumulator
    push dx                 ;   (kernel keeps it on the stack between blocks)
    xor si, si              ; SI = 0: offset of the marker within the MCB

walk:
    es lodsb                ; AL = marker
    mov [M_MARKER], al
    es lodsw                ; AX = owner
    mov [M_OWNER], ax
    es lodsw                ; AX = size
    mov cx, ax              ; CX = size (kernel 0x6A0C: mov cx,[0x3])

    mov ax, [M_OWNER]
    test ax, ax
    jnz owned               ; owned block: no largest/fit bookkeeping

    ; free block: largest so far (kernel 0x6A11-0x6A15: pop dx / cmp cx,dx /
    ; jna / mov dx,cx / push dx -- push always executes).
    pop dx
    cmp cx, dx
    jna no_update
    mov dx, cx
no_update:
    push dx

    ; the fit compare (kernel 0x6A18-0x6A1A: cmp bx,cx / ja): BX = request.
    mov bx, REQ
    cmp bx, cx
    ja not_fit
    inc word [M_FITS]       ; this free block fits the request
not_fit:

owned:
    ; end of chain? (kernel 0x69C2: cmp byte [di],5A / jz)
    cmp byte [M_MARKER], 'Z'
    je walk_done

    ; chain step (kernel 0x6920-0x6926: mov ax,ds / add ax,[0x3] / inc ax).
    ; DS is 0 here, so read the size through the ES override - the same opcode
    ; stream as the kernel's, minus the segment override.
    mov ax, es
    add ax, [es:3]
    inc ax
    mov es, ax
    xor si, si
    jmp walk

walk_done:
    pop dx                  ; DX = largest free block

    ; the caller-visible frame store (kernel 0x611 mov [si],ax and
    ; 0x69FD mov [si+2],bx): AX = error code, BX = largest free.
    mov si, FRAME
    mov ax, ERR_NOMEM
    mov bx, dx
    mov [si], ax
    mov [si+2], bx

    ; ---- assert -----------------------------------------------------------
    cmp dx, 0x5208
    jne fail1

    cmp word [M_FITS], 1
    jne fail2

    ; the frame store round-trips through RAM.
    cmp word [FRAME], ERR_NOMEM
    jne fail3
    cmp word [FRAME+2], 0x5208
    jne fail4

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail1: mov ax, 1
       jmp fail
fail2: mov ax, 2
       jmp fail
fail3: mov ax, 3
       jmp fail
fail4: mov ax, 4
       jmp fail

fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
