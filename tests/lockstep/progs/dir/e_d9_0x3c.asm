; reserved x87 memory form DB /6 with CR0.EM = 0 on a core without x87
org 0
times 0x100 db 0
  mov eax, 0x11112222
  mov ecx, 0x33334444
  mov si, 0x200
  db 0xd9, 0x3c
  mov ebx, 0x5555
  hlt
