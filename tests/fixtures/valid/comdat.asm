bits 64
default rel

%include "seh64.inc"

section .text
global seh64_comdat_entry
global seh64_comdat_kept
global seh64_comdat_dead
global seh64_comdat_chain_parent
global seh64_comdat_chain_child
global seh64_comdat_chain_grandchild

; Direct control transfers between COMDAT sections are ordinary COFF REL32
; relocations. NASM 3.x includes its generic cross-section warning in -Wall.
%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning push]
    [warning -reloc-rel-dword]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning -reloc-rel-dword]
%endif

seh64_comdat_entry:
    sub rsp, 0x28
    call seh64_comdat_kept
    call seh64_comdat_chain_parent
    add rsp, 0x28
    ret

SEH_PROC_COMDAT seh64_comdat_kept
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG

    xor eax, eax
    add rsp, 0x28
    ret
SEH_ENDPROC

SEH_PROC_COMDAT seh64_comdat_dead
    SEH_ALLOCSTACK 0x38
    SEH_ENDPROLOG

    xor eax, eax
    add rsp, 0x38
    ret
SEH_ENDPROC

SEH_PROC_COMDAT seh64_comdat_chain_parent
    SEH_PUSHREG rbp
    SEH_ALLOCSTACK 0x20
    SEH_SETFRAME rbp, 0
    SEH_ENDPROLOG

    jmp seh64_comdat_chain_child
SEH_ENDPROC

SEH_CHAIN_PROC seh64_comdat_chain_child, seh64_comdat_chain_parent
    SEH_SAVEREG r12, 0x10
    SEH_ENDPROLOG

    jmp seh64_comdat_chain_grandchild
SEH_ENDPROC

SEH_CHAIN_PROC seh64_comdat_chain_grandchild, seh64_comdat_chain_child
    SEH_SAVEREG r13, 0x18
    SEH_ENDPROLOG

    mov r13, [rsp + 0x18]
    mov r12, [rsp + 0x10]
    add rsp, 0x20
    pop rbp
    ret
SEH_ENDPROC

%if __?NASM_VERSION_ID?__ >= 0x03020000
    [warning pop]
%elif __?NASM_VERSION_ID?__ >= 0x03010000
    [warning *reloc-rel-dword]
%endif
