.code

PUBLIC seh64_masm_reference

seh64_masm_reference PROC FRAME
    push rbp
    .pushreg rbp
    push rbx
    .pushreg rbx
    sub rsp, 48h
    .allocstack 48h
    lea rbp, [rsp + 20h]
    .setframe rbp, 20h
    mov [rsp + 30h], rsi
    .savereg rsi, 30h
    movdqa xmmword ptr [rsp + 10h], xmm6
    .savexmm128 xmm6, 10h
    .endprolog

    mov eax, ecx

    movdqa xmm6, xmmword ptr [rsp + 10h]
    mov rsi, [rsp + 30h]
    add rsp, 48h
    pop rbx
    pop rbp
    ret
seh64_masm_reference ENDP

END
