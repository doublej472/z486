; 486 XADD/CMPXCHG byte/word aliases, upper-lane preservation and flags.
; Expected values follow sized ADD and accumulator-minus-destination SUB.
BITS 32
ORG 0
%macro FLAGS 1
    pushfd
    pop esi
    and esi, 0x8d5           ; OF/SF/ZF/AF/PF/CF
    cmp esi, %1
    jne fail
%endmacro
start:
    mov esp, 0x2000
    mov eax, 0xaabb007f
    mov ebx, 0x11220001
    xadd al, bl
    FLAGS 0x890             ; 7f+1=80: OF/SF/AF
    cmp eax, 0xaabb0080
    jne fail
    cmp ebx, 0x1122007f
    jne fail

    mov eax, 0xbbcc12f0
    xadd ah, al
    FLAGS 1                 ; 12+f0=102: CF only
    cmp eax, 0xbbcc0212
    jne fail

    mov eax, 0xabcd8000
    xadd ax, ax
    FLAGS 0x845             ; 8000+8000=0: OF/ZF/PF/CF
    cmp eax, 0xabcd0000
    jne fail

    mov eax, 0xcafe8088
    xadd ah, ah
    FLAGS 0x845
    cmp eax, 0xcafe0088
    jne fail

    mov eax, 0xabcd3434
    mov ebx, 0xdeadbe67
    cmpxchg ah, bl
    FLAGS 0x44              ; equal: ZF/PF
    cmp eax, 0xabcd6734
    jne fail
    cmp ebx, 0xdeadbe67
    jne fail

    mov eax, 0xabcd8010
    cmpxchg ah, bl
    FLAGS 0x885             ; 10-80=90: OF/SF/PF/CF
    cmp eax, 0xabcd8080
    jne fail

    mov eax, 0x12345678
    cmpxchg al, ah           ; destination aliases accumulator: always equal
    FLAGS 0x44
    cmp eax, 0x12345656
    jne fail

    mov dword [0x4000], 0x1234ffff
    mov eax, 0xfffe0001
    lock xadd word [0x4000], ax
    FLAGS 0x55              ; ffff+1=0: ZF/AF/PF/CF
    cmp eax, 0xfffeffff
    jne fail
    cmp dword [0x4000], 0x12340000
    jne fail

    mov dword [0x4000], 0xabcd8000
    mov eax, 0xfeed0001
    mov edx, 0x12345678
    lock cmpxchg word [0x4000], dx
    FLAGS 0x881             ; 1-8000=8001: OF/SF/CF
    cmp eax, 0xfeed8000
    jne fail
    cmp dword [0x4000], 0xabcd8000
    jne fail

    mov eax, 0xc0de8000
    cmpxchg word [0x4000], dx
    FLAGS 0x44
    cmp dword [0x4000], 0xabcd5678
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, esi
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
