bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_alloc_after_save
    SEH_PUSHREG rbp
    SEH_SAVEREG rbx, 0x10
    SEH_ALLOCSTACK 0x20
    SEH_ENDPROLOG
    pop rbp
    ret
SEH_ENDPROC
