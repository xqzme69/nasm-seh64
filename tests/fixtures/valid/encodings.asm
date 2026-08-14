bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_alloc_small_last
    SEH_PUSHREG rbx
    SEH_ALLOCSTACK 128
    SEH_ENDPROLOG
    add rsp, 128
    pop rbx
    ret
SEH_ENDPROC

SEH_PROC seh64_alloc_large0_first
    SEH_ALLOCSTACK 136
    SEH_ENDPROLOG
    add rsp, 136
    ret
SEH_ENDPROC

SEH_PROC seh64_alloc_large0_last
    SEH_ALLOCSTACK 0x7fff8
    SEH_ENDPROLOG
    add rsp, 0x7fff8
    ret
SEH_ENDPROC

SEH_PROC seh64_alloc_large1_first
    SEH_PUSHREG rbx
    SEH_ALLOCSTACK 0x80000
    SEH_ENDPROLOG
    add rsp, 0x80000
    pop rbx
    ret
SEH_ENDPROC

SEH_PROC seh64_save_gpr_far_first
    SEH_ALLOCSTACK 0x80008
    SEH_SAVEREG r12, 0x80000
    SEH_ENDPROLOG
    mov r12, [rsp + 0x80000]
    add rsp, 0x80008
    ret
SEH_ENDPROC

SEH_PROC seh64_save_xmm_far_first
    SEH_ALLOCSTACK 0x100018
    SEH_SAVEXMM xmm15, 0x100000
    SEH_ENDPROLOG
    movdqa xmm15, [rsp + 0x100000]
    add rsp, 0x100018
    ret
SEH_ENDPROC
