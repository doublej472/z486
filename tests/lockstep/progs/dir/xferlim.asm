; control transfer to an EIP beyond the CS limit: #GP(0) at the transfer, pushed IP = the JMP
; (i486 PRM JMP/CALL/RET: "IF instruction pointer not within code segment limit THEN #GP(0)")
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:13*4], h13
  mov word [es:13*4+2], 0x1000
  mov eax, 0x00012345
  jmp eax                ; 66 FF E0
back:
  mov eax, 0x00010000
  call eax
back2:
  hlt
h13:
  pop bx                 ; pushed IP
  pop cx                 ; pushed CS
  pop dx                 ; FLAGS
  mov [es:0x500], bx
  cmp bx, 0x2345
  je .tgt
  add bx, 3              ; skip the 3-byte JMP / CALL
.tgt:
  inc si
  cmp si, 2
  jae back2
  jmp back
