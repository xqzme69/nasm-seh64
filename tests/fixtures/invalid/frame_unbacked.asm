bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_frame_unbacked
    SEH_PUSHREG rbp
    SEH_SETFRAME rbp, 0x10
    SEH_ENDPROLOG
    pop rbp
    ret
SEH_ENDPROC
