bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_push_after_alloc
    SEH_ALLOCSTACK 0x28
    SEH_PUSHREG rbx
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC
