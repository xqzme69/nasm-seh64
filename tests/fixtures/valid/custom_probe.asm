bits 64
default rel

%define SEH64_STACK_PROBE local_stack_probe
%define SEH64_STACK_PROBE_EXTERNAL 0
%include "seh64.inc"

section .text

local_stack_probe:
    ret

SEH_PROC seh64_custom_probe
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x1000
    SEH_ENDPROLOG
    add rsp, 0x1000
    pop rbp
    ret
SEH_ENDPROC
