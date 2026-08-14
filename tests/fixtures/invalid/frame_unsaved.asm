bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_frame_unsaved
    SEH_ALLOCSTACK 0x28
    SEH_SETFRAME rbp, 0
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC
