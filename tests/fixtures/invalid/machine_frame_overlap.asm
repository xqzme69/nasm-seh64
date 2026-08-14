bits 64

%include "seh64.inc"

section .text

SEH_PROC invalid_machine_frame_overlap
    SEH_PUSHFRAME 1
    SEH_ALLOCSTACK 0x20
    SEH_SAVEREG rbx, 0x30
    SEH_ENDPROLOG
    add rsp, 0x20
    ret
SEH_ENDPROC
