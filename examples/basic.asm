bits 64
default rel

%include "seh64.inc"

section .text
global seh64_example

SEH_PROC seh64_example
    SEH_PUSHREG rbp
    SEH_PUSHREG rbx
    SEH_ALLOCSTACK 0x48
    SEH_SETFRAME rbp, 0x20
    SEH_SAVEREG rsi, 0x30
    SEH_SAVEXMM xmm6, 0x10
    SEH_ENDPROLOG

    mov eax, ecx

    movdqa xmm6, [rsp + 0x10]
    mov rsi, [rsp + 0x30]
    add rsp, 0x48
    pop rbx
    pop rbp
    ret
SEH_ENDPROC
