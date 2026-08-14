bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_multichain_primary
    SEH_ALLOCSTACK 0x38
    SEH_ENDPROLOG
    add rsp, 0x38
    ret
SEH_ENDPROC

SEH_CHAIN_PROC seh64_multichain_first, seh64_multichain_primary
    SEH_SAVEREG r12, 0
    SEH_ENDPROLOG
    mov r12, [rsp]
    ret
SEH_ENDPROC

SEH_CHAIN_PROC seh64_multichain_second, seh64_multichain_first
    SEH_SAVEREG r13, 8
    SEH_ENDPROLOG
    mov r13, [rsp + 8]
    ret
SEH_ENDPROC
