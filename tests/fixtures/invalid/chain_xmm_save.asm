bits 64

%include "seh64.inc"

section .text

SEH_PROC chain_xmm_parent
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_CHAIN_PROC invalid_chain_xmm_save, chain_xmm_parent
    SEH_SAVEXMM xmm6, 0x10
    SEH_ENDPROLOG
    ret
SEH_ENDPROC
