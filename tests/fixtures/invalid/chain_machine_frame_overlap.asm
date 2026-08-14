bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_chain_machine_frame_parent
    SEH_PUSHFRAME
    SEH_ENDPROLOG
    jmp invalid_chain_machine_frame_child
SEH_ENDPROC

SEH_CHAIN_PROC invalid_chain_machine_frame_child, invalid_chain_machine_frame_parent
    SEH_SAVEREG rbx, 8
    SEH_ENDPROLOG
    mov rbx, [rsp + 8]
    ret
SEH_ENDPROC
