bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_machine_frame
    SEH_PUSHFRAME 1
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x20
    SEH_SETFRAME rbp, 0
    SEH_ENDPROLOG

    jmp seh64_machine_frame_child
SEH_ENDPROC

SEH_CHAIN_PROC seh64_machine_frame_child, seh64_machine_frame
    SEH_SAVEREG rbx, 0
    SEH_ENDPROLOG

    mov rbx, [rsp]
    add rsp, 0x20
    pop rbp
    ret
SEH_ENDPROC
