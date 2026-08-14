bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_save_overlap
    SEH_ALLOCSTACK 0x28
    SEH_SAVEREG rbx, 0x28
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC
