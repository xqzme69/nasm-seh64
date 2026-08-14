bits 64
default rel

%include "seh64.inc"

%macro seh64_handler_payload 0
    dd 0x53454836
%endmacro

section .text
global seh64_handler_fixture
global seh64_test_handler

SEH_PROC seh64_handler_fixture
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER seh64_test_handler, SEH64_EHANDLER | SEH64_UHANDLER, seh64_handler_payload
    SEH_ENDPROLOG

    xor eax, eax
    add rsp, 0x28
    ret
SEH_ENDPROC

seh64_test_handler:
    mov eax, 1
    ret
