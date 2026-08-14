bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_alloc_unaligned
    SEH_ALLOCSTACK 13
    SEH_ENDPROLOG
    ret
SEH_ENDPROC
