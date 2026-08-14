bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_chain_save_slot_parent
    SEH_ALLOCSTACK 0x28
    SEH_SAVEREG rbx, 0
    SEH_ENDPROLOG
    jmp invalid_chain_save_slot_child
SEH_ENDPROC

SEH_CHAIN_PROC invalid_chain_save_slot_child, invalid_chain_save_slot_parent
    SEH_SAVEREG r12, 0
    SEH_ENDPROLOG
    mov r12, [rsp]
    mov rbx, [rsp]
    add rsp, 0x28
    ret
SEH_ENDPROC
