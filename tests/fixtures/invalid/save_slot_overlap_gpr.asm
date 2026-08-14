bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_save_slot_overlap_gpr
    SEH_ALLOCSTACK 0x28
    SEH_SAVEXMM xmm6, 0
    SEH_SAVEREG rbx, 8
    SEH_ENDPROLOG
    mov rbx, [rsp + 8]
    movdqa xmm6, [rsp]
    add rsp, 0x28
    ret
SEH_ENDPROC
