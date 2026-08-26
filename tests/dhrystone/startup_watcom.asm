.386p
.model flat

_TEXT segment byte public use32 'CODE'
assume cs:_TEXT

public _start
extrn dhrystone_main_:near

_start:
    cld
    call dhrystone_main_

    mov dx, 00e4h
    out dx, eax

    test eax, eax
    jnz failed
    mov eax, 01h
    jmp report_status

failed:
    mov eax, 0ffh

report_status:
    mov dx, 00e0h
    out dx, al

halt:
    hlt
    jmp halt

_TEXT ends
end _start
