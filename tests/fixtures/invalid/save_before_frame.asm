bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_save_before_frame
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x30
    SEH_SAVEREG rbx, 0
    SEH_SETFRAME rbp, 0x10
    SEH_ENDPROLOG
    mov rbx, [rsp]
    add rsp, 0x30
    pop rbp
    ret
SEH_ENDPROC
