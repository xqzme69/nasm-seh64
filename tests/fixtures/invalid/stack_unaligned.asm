bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_stack_unaligned
    SEH_PUSHREG rbx
    SEH_PUSHREG rsi
    SEH_ENDPROLOG
    pop rsi
    pop rbx
    ret
SEH_ENDPROC
