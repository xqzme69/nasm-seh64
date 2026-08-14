bits 64
default rel

%include "seh64.inc"

%macro runtime_handler_payload 0
    dd 0x53454836
%endmacro

%macro runtime_raise_payload 0
    dd 0x45534952
%endmacro

%macro runtime_av_payload 0
    dd 0x20205641
%endmacro

%macro runtime_divide_payload 0
    dd 0x20564944
%endmacro

%macro runtime_unwind_inner_payload 0
    dd 0x524e4e49
%endmacro

%macro runtime_unwind_outer_payload 0
    dd 0x5254554f
%endmacro

%define RUNTIME_EXCEPTION_CODE 0xe0646401

extern RaiseException
extern seh64_runtime_dispatch_handler
extern seh64_runtime_catch_unwind

section .rdata align=16
align 16
runtime_xmm_seed:
    dq 0x0123456789abcdef, 0xfedcba9876543210

section .text
global seh64_runtime_target
global seh64_runtime_after_push_rbp
global seh64_runtime_after_push_rbx
global seh64_runtime_after_alloc
global seh64_runtime_after_setframe
global seh64_runtime_after_save_rsi
global seh64_runtime_after_save_xmm6
global seh64_runtime_body
global seh64_runtime_call_probe
global seh64_runtime_handler_target
global seh64_runtime_handler_body
global seh64_runtime_handler
global seh64_runtime_chain_parent
global seh64_runtime_chain_child
global seh64_runtime_chain_body
global seh64_runtime_machframe
global seh64_runtime_machframe_body
global seh64_runtime_machframe_error
global seh64_runtime_machframe_error_body
global seh64_runtime_return_marker
global seh64_runtime_raise_dispatch
global seh64_runtime_av_dispatch
global seh64_runtime_av_resume
global seh64_runtime_divide_dispatch
global seh64_runtime_divide_resume
global seh64_runtime_unwind_probe
global seh64_runtime_unwind_outer
global seh64_runtime_unwind_inner

SEH_PROC seh64_runtime_target
    SEH_PUSHREG rbp
seh64_runtime_after_push_rbp:
    SEH_PUSHREG rbx
seh64_runtime_after_push_rbx:
    SEH_ALLOCSTACK 0x48
seh64_runtime_after_alloc:
    SEH_SETFRAME rbp, 0x20
seh64_runtime_after_setframe:
    SEH_SAVEREG rsi, 0x30
seh64_runtime_after_save_rsi:
    SEH_SAVEXMM xmm6, 0x10
seh64_runtime_after_save_xmm6:
    SEH_ENDPROLOG

    nop
seh64_runtime_body:
    mov rbx, 0xaaaaaaaaaaaaaaaa
    mov rsi, 0xbbbbbbbbbbbbbbbb
    pcmpeqd xmm6, xmm6
    lea eax, [rcx + 1]

    movdqa xmm6, [rsp + 0x10]
    mov rsi, [rsp + 0x30]
    add rsp, 0x48
    pop rbx
    pop rbp
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_call_probe
    SEH_PUSHREG rbp
    SEH_PUSHREG rbx
    SEH_PUSHREG rsi
    SEH_ALLOCSTACK 0x30
    SEH_SAVEXMM xmm6, 0x20
    SEH_ENDPROLOG

    mov rbx, 0x1122334455667788
    mov rsi, 0x8877665544332211
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning push]
    [warning -reloc-rel-dword]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning -reloc-rel-dword]
%endif
    movdqa xmm6, [rel runtime_xmm_seed]
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning pop]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning *reloc-rel-dword]
%endif
    mov ecx, 41
    call seh64_runtime_target

    cmp eax, 42
    jne .failed
    mov rax, 0x1122334455667788
    cmp rbx, rax
    jne .failed
    mov rax, 0x8877665544332211
    cmp rsi, rax
    jne .failed

    movdqa xmm0, xmm6
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning push]
    [warning -reloc-rel-dword]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning -reloc-rel-dword]
%endif
    pcmpeqb xmm0, [rel runtime_xmm_seed]
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning pop]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning *reloc-rel-dword]
%endif
    pmovmskb eax, xmm0
    cmp eax, 0xffff
    jne .failed

    mov eax, 1
    jmp .done

.failed:
    xor eax, eax

.done:
    movdqa xmm6, [rsp + 0x20]
    add rsp, 0x30
    pop rsi
    pop rbx
    pop rbp
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_handler_target
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER seh64_runtime_handler, SEH64_EHANDLER, runtime_handler_payload
    SEH_ENDPROLOG

    nop
seh64_runtime_handler_body:
    xor eax, eax
    add rsp, 0x28
    ret
SEH_ENDPROC

seh64_runtime_handler:
    xor eax, eax
    ret

SEH_PROC seh64_runtime_chain_parent
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x20
    SEH_SETFRAME rbp, 0
    SEH_ENDPROLOG

    jmp seh64_runtime_chain_child
SEH_ENDPROC

SEH_CHAIN_PROC seh64_runtime_chain_child, seh64_runtime_chain_parent
    SEH_SAVEREG r12, 0x10
    SEH_ENDPROLOG

    nop
seh64_runtime_chain_body:
    mov r12, 0xcccccccccccccccc
    mov r12, [rsp + 0x10]
    add rsp, 0x20
    pop rbp
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_machframe
    SEH_PUSHFRAME 0
    SEH_ENDPROLOG

    nop
seh64_runtime_machframe_body:
    xor eax, eax
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_machframe_error
    SEH_PUSHFRAME 1
    SEH_ENDPROLOG

    nop
seh64_runtime_machframe_error_body:
    xor eax, eax
    ret
SEH_ENDPROC

; NASM 3.x puts ordinary unresolved COFF REL32 calls in this generic warning
; category. Keep -Wall -Werror active for the rest of the fixture.
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning push]
    [warning -reloc-rel-dword]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning -reloc-rel-dword]
%endif

SEH_PROC seh64_runtime_raise_dispatch
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER seh64_runtime_dispatch_handler, SEH64_EHANDLER, runtime_raise_payload
    SEH_ENDPROLOG

    mov ecx, RUNTIME_EXCEPTION_CODE
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call RaiseException
seh64_runtime_raise_resume:
    mov eax, 1
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_av_dispatch
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER seh64_runtime_dispatch_handler, SEH64_EHANDLER, runtime_av_payload
    SEH_ENDPROLOG

    xor eax, eax
    mov eax, [rax]
seh64_runtime_av_resume:
    mov eax, 1
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_divide_dispatch
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER seh64_runtime_dispatch_handler, SEH64_EHANDLER, runtime_divide_payload
    SEH_ENDPROLOG

    xor edx, edx
    mov eax, 1
    div edx
seh64_runtime_divide_resume:
    mov eax, 1
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_unwind_probe
    SEH_PUSHREG rbx
    SEH_PUSHREG rsi
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG

    mov rbx, 0x1122334455667788
    mov rsi, 0x8877665544332211
    call seh64_runtime_catch_unwind
    cmp eax, 1
    jne .failed
    mov rax, 0x1122334455667788
    cmp rbx, rax
    jne .failed
    mov rax, 0x8877665544332211
    cmp rsi, rax
    jne .failed
    mov eax, 1
    jmp .done

.failed:
    xor eax, eax

.done:
    add rsp, 0x28
    pop rsi
    pop rbx
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_unwind_outer
    SEH_PUSHREG rbx
    SEH_ALLOCSTACK 0x20
    SEH_HANDLER seh64_runtime_dispatch_handler, SEH64_UHANDLER, runtime_unwind_outer_payload
    SEH_ENDPROLOG

    mov rbx, 0xaaaaaaaaaaaaaaaa
    call seh64_runtime_unwind_inner
    xor eax, eax
    add rsp, 0x20
    pop rbx
    ret
SEH_ENDPROC

SEH_PROC seh64_runtime_unwind_inner
    SEH_PUSHREG rsi
    SEH_ALLOCSTACK 0x20
    SEH_HANDLER seh64_runtime_dispatch_handler, SEH64_UHANDLER, runtime_unwind_inner_payload
    SEH_ENDPROLOG

    mov rsi, 0xbbbbbbbbbbbbbbbb
    mov ecx, RUNTIME_EXCEPTION_CODE
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call RaiseException
    xor eax, eax
    add rsp, 0x20
    pop rsi
    ret
SEH_ENDPROC

%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning pop]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning *reloc-rel-dword]
%endif

seh64_runtime_return_marker:
    ret
