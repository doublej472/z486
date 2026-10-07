; nw_lock - CR0.CD=1/NW=1: locked RMW on a cached line
;
; A locked read bypasses a valid line and reads memory; with NW=1 the locked
; write hits the line and stays cache-only.  Two LOCK INC of a cached dword
; must still add 2 (the CPU must observe its own stores).
; Failure data = the value read back.
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov dword [0x34000], 10
    mov eax, [0x34000]                ; allocate the line (CD=0)
    mov ecx, cr0
    or ecx, 0x60000000                ; CD=1, NW=1
    mov cr0, ecx
    lock inc dword [0x34000]
    lock inc dword [0x34000]
    mov ebx, [0x34000]
    and ecx, ~0x60000000
    mov cr0, ecx
    cmp ebx, 12
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, ebx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
