bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_chain_parent
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x20
    SEH_SETFRAME rbp, 0
    SEH_ENDPROLOG

    add rsp, 0x20
    pop rbp
    ret
SEH_ENDPROC

SEH_CHAIN_PROC seh64_chain_child, seh64_chain_parent
    SEH_SAVEREG r12, 0x10
    SEH_ENDPROLOG

    mov r12, [rsp + 0x10]
    ret
SEH_ENDPROC
