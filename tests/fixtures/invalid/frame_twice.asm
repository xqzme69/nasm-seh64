bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_frame_twice
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x20
    SEH_SETFRAME rbp, 0
    SEH_SETFRAME r13, 0x10
    SEH_ENDPROLOG
    add rsp, 0x20
    pop rbp
    ret
SEH_ENDPROC
