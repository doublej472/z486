org 0
times 0x100 db 0
  mov ax, 0x2000
  mov ds, ax
  mov es, ax
  mov dword [0x20], 0x30503050
  mov dword [0x24], 0x30503050
  mov word [0x28], 0x5030
  cld
  mov di, 0x20
  mov cx, 10
  mov al, 0x40
  stc
  repne scasb
  pushf
  pop ax
  mov bx, ax
  mov ax, 0x1234
  mov cx, 2
  mov di, 0x20
  repne scasb
  into
  hlt
