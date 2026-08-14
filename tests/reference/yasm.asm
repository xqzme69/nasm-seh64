bits 64
default rel

section .text
global seh64_yasm_reference

proc_frame seh64_yasm_reference
    push_reg rbp
    push_reg rbx
    alloc_stack 0x48
    set_frame rbp, 0x20
    save_reg rsi, 0x30
    save_xmm128 xmm6, 0x10
    end_prolog

    mov eax, ecx

    movdqa xmm6, [rsp + 0x10]
    mov rsi, [rsp + 0x30]
    add rsp, 0x48
    pop rbx
    pop rbp
    ret
endproc_frame
