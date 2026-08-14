bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_xmm_address_unaligned
    SEH_ALLOCSTACK 0x20
    SEH_SAVEXMM xmm6, 0
    SEH_ENDPROLOG
    add rsp, 0x20
    ret
SEH_ENDPROC
