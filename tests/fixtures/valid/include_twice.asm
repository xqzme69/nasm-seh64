bits 64
default rel

%include "seh64.inc"
%include "seh64.inc"

section .text

SEH_PROC seh64_included_twice
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG
    add rsp, 0x28
    ret
SEH_ENDPROC
