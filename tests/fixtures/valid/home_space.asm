bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_home_space
    SEH_PUSHREG rbp
    SEH_SAVEREG rbx, 0x10
    SEH_SAVEXMM xmm6, 0x20
    SEH_ENDPROLOG

    movdqa xmm6, [rsp + 0x20]
    mov rbx, [rsp + 0x10]
    pop rbp
    ret
SEH_ENDPROC
