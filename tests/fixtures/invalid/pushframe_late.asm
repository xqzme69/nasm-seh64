bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_pushframe_late
    SEH_PUSHREG rbp
    SEH_PUSHFRAME
    SEH_ENDPROLOG
    pop rbp
    ret
SEH_ENDPROC
