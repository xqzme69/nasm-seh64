bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_xmm_offset_unaligned
    SEH_ALLOCSTACK 0x28
    SEH_SAVEXMM xmm6, 0x13
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC
