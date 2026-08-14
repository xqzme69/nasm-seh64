bits 64
default rel

%include "seh64.inc"

section .text

SEH_PROC seh64_all_nonvolatile_gprs
    SEH_PUSHREG rbx
    SEH_PUSHREG rbp
    SEH_PUSHREG rsi
    SEH_PUSHREG rdi
    SEH_PUSHREG r12
    SEH_PUSHREG r13
    SEH_PUSHREG r14
    SEH_PUSHREG r15
    SEH_ALLOCSTACK 8
    SEH_ENDPROLOG

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    ret
SEH_ENDPROC

SEH_PROC seh64_all_nonvolatile_xmms
    SEH_ALLOCSTACK 0xa8
    SEH_SAVEXMM xmm6, 0x00
    SEH_SAVEXMM xmm7, 0x10
    SEH_SAVEXMM xmm8, 0x20
    SEH_SAVEXMM xmm9, 0x30
    SEH_SAVEXMM xmm10, 0x40
    SEH_SAVEXMM xmm11, 0x50
    SEH_SAVEXMM xmm12, 0x60
    SEH_SAVEXMM xmm13, 0x70
    SEH_SAVEXMM xmm14, 0x80
    SEH_SAVEXMM xmm15, 0x90
    SEH_ENDPROLOG

    movdqa xmm15, [rsp + 0x90]
    movdqa xmm14, [rsp + 0x80]
    movdqa xmm13, [rsp + 0x70]
    movdqa xmm12, [rsp + 0x60]
    movdqa xmm11, [rsp + 0x50]
    movdqa xmm10, [rsp + 0x40]
    movdqa xmm9, [rsp + 0x30]
    movdqa xmm8, [rsp + 0x20]
    movdqa xmm7, [rsp + 0x10]
    movdqa xmm6, [rsp + 0x00]
    add rsp, 0xa8
    ret
SEH_ENDPROC

SEH_PROC seh64_high_frame_register
    SEH_PUSHREG r13
    SEH_ALLOCSTACK 0x100
    SEH_SETFRAME r13, 0xf0
    SEH_ENDPROLOG

    add rsp, 0x100
    pop r13
    ret
SEH_ENDPROC
