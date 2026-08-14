bits 64

%include "seh64.inc"

section .text

SEH_PROC chain_handler_parent
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_CHAIN_PROC invalid_chain_handler, chain_handler_parent
    SEH_HANDLER chain_handler_target, SEH64_EHANDLER
    SEH_ENDPROLOG
    ret
SEH_ENDPROC

chain_handler_target:
    ret
