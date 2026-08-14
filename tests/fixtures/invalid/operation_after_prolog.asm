bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_operation_after_prolog
    SEH_ENDPROLOG
    SEH_PUSHREG rbx
    ret
SEH_ENDPROC
