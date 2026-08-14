bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_volatile_push
    SEH_PUSHREG rax
    SEH_ENDPROLOG
    ret
SEH_ENDPROC
