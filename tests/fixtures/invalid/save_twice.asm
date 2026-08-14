bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_save_twice
    SEH_ALLOCSTACK 0x38
    SEH_SAVEREG rbx, 0
    SEH_SAVEREG rbx, 8
    SEH_ENDPROLOG
    mov rbx, [rsp]
    add rsp, 0x38
    ret
SEH_ENDPROC
