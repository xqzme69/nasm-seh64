bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_prolog_too_long
    times 256 nop
    SEH_ENDPROLOG
    ret
SEH_ENDPROC
