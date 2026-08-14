bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_handler_flags
    SEH_HANDLER invalid_handler_target, SEH64_CHAININFO
    SEH_ENDPROLOG
    ret
SEH_ENDPROC

invalid_handler_target:
    ret
