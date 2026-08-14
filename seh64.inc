; nasm-seh64 0.1.0
; Copyright (c) 2026 xqzme69. Distributed under the MIT license.

%ifndef __SEH64_INCLUDED
%define __SEH64_INCLUDED 1

%macro __seh64_error 2+
    %ifctx seh64
        %error seh64: %$name: %1: %2
    %else
        %error seh64: %1: %2
    %endif
%endmacro

%ifnidn __OUTPUT_FORMAT__, win64
    __seh64_error SEH64-E001, only NASM -f win64 is supported
%endif

%define SEH64_VERSION 0x000100

%define SEH64_EHANDLER  0x01
%define SEH64_UHANDLER  0x02
%define SEH64_CHAININFO 0x04

%ifndef SEH64_STACK_PROBE
    %define SEH64_STACK_PROBE __chkstk
%endif

%ifndef SEH64_STACK_PROBE_THRESHOLD
    %define SEH64_STACK_PROBE_THRESHOLD 4096
%endif

%ifndef SEH64_STACK_PROBE_EXTERNAL
    %define SEH64_STACK_PROBE_EXTERNAL 1
%endif

%if SEH64_STACK_PROBE_THRESHOLD <= 0
    __seh64_error SEH64-E002, SEH64_STACK_PROBE_THRESHOLD must be positive
%endif

%if (SEH64_STACK_PROBE_EXTERNAL != 0) && (SEH64_STACK_PROBE_EXTERNAL != 1)
    __seh64_error SEH64-E003, SEH64_STACK_PROBE_EXTERNAL must be 0 or 1
%endif

%define __SEH64_KIND_PUSH       1
%define __SEH64_KIND_ALLOC      2
%define __SEH64_KIND_SET_FRAME  3
%define __SEH64_KIND_SAVE_GPR   4
%define __SEH64_KIND_SAVE_XMM   5
%define __SEH64_KIND_MACH_FRAME 6

%define __SEH64_MODE_NORMAL  0
%define __SEH64_MODE_CHAINED 1

%define __SEH64_COMDAT_NONE        0
%define __SEH64_COMDAT_ROOT        1
%define __SEH64_COMDAT_ASSOCIATIVE 5

%macro __seh64_nonvolatile_gpr 1
    %assign %$reg_id -1
    %ifidni %1, rbx
        %assign %$reg_id 3
    %elifidni %1, rbp
        %assign %$reg_id 5
    %elifidni %1, rsi
        %assign %$reg_id 6
    %elifidni %1, rdi
        %assign %$reg_id 7
    %elifidni %1, r12
        %assign %$reg_id 12
    %elifidni %1, r13
        %assign %$reg_id 13
    %elifidni %1, r14
        %assign %$reg_id 14
    %elifidni %1, r15
        %assign %$reg_id 15
    %endif
%endmacro

%macro __seh64_nonvolatile_xmm 1
    %assign %$reg_id -1
    %ifidni %1, xmm6
        %assign %$reg_id 6
    %elifidni %1, xmm7
        %assign %$reg_id 7
    %elifidni %1, xmm8
        %assign %$reg_id 8
    %elifidni %1, xmm9
        %assign %$reg_id 9
    %elifidni %1, xmm10
        %assign %$reg_id 10
    %elifidni %1, xmm11
        %assign %$reg_id 11
    %elifidni %1, xmm12
        %assign %$reg_id 12
    %elifidni %1, xmm13
        %assign %$reg_id 13
    %elifidni %1, xmm14
        %assign %$reg_id 14
    %elifidni %1, xmm15
        %assign %$reg_id 15
    %endif
%endmacro

%macro __seh64_record 5
    %if %$op_count = 0
        %xdefine %$ops %1, %2, %3, %4
    %else
        %xdefine %$ops %1, %2, %3, %4, %$ops
    %endif
    %assign %$op_count %$op_count + 1
    %assign %$slot_count %$slot_count + %5
%endmacro

%macro __seh64_record_save_range 2
    %if %$save_range_count = 0
        %xdefine %$save_ranges %1, %2
    %else
        %xdefine %$save_ranges %$save_ranges, %1, %2
    %endif
    %assign %$save_range_count %$save_range_count + 1
%endmacro

%macro __seh64_scan_save_ranges 2-*
    %rep %0 / 2
        %assign %$saved_range_end %1 + %2
        %if (%$candidate_begin < %$saved_range_end) && (%$candidate_end > %1)
            %assign %$save_range_conflict 1
        %endif
        %rotate 2
    %endrep
%endmacro

%macro __seh64_check_save_range 2
    %assign %$save_range_conflict 0
    %assign %$candidate_begin %1
    %assign %$candidate_end %1 + %2
    %if %$save_range_count > 0
        __seh64_scan_save_ranges %$save_ranges
    %endif
%endmacro

%macro __seh64_check_save_slot 2
    %assign %$save_slot_ok 1
    %assign %$save_slot_backed 0
    %assign %$save_end %1 + %2
    %assign %$protected_begin %$alloc_bytes
    %if %$mach_frame
        %assign %$protected_end %$alloc_bytes + %$push_bytes + %$mach_frame_bytes
    %else
        %assign %$protected_end %$alloc_bytes + %$push_bytes + 8
    %endif

    ; Pushed state, the return address, or a machine frame live here.
    %if (%1 < %$protected_end) && (%$save_end > %$protected_begin)
        %assign %$save_slot_ok 0
    %endif

    %if (%1 >= 0) && (%$save_end <= %$alloc_bytes)
        %assign %$save_slot_backed 1
    %elif (%$mach_frame = 0) && (%1 >= %$protected_end) && (%$save_end <= %$protected_end + 32)
        %assign %$save_slot_backed 1
    %endif
%endmacro

%macro __seh64_emit_ops 4-*
    %rep %0 / 4
        db %2 - %$begin

        %if %1 = __SEH64_KIND_PUSH
            db (%3 << 4) | 0
        %elif %1 = __SEH64_KIND_ALLOC
            %if %4 <= 128
                db (((%4 - 8) / 8) << 4) | 2
            %elif %4 <= 0x7fff8
                db 1
                dw %4 / 8
            %else
                db 0x11
                dd %4
            %endif
        %elif %1 = __SEH64_KIND_SET_FRAME
            db 3
        %elif %1 = __SEH64_KIND_SAVE_GPR
            %if %4 <= 0x7fff8
                db (%3 << 4) | 4
                dw %4 / 8
            %else
                db (%3 << 4) | 5
                dd %4
            %endif
        %elif %1 = __SEH64_KIND_SAVE_XMM
            %if %4 <= 0xffff0
                db (%3 << 4) | 8
                dw %4 / 16
            %else
                db (%3 << 4) | 9
                dd %4
            %endif
        %elif %1 = __SEH64_KIND_MACH_FRAME
            db (%3 << 4) | 10
        %else
            __seh64_error SEH64-E900, internal unknown unwind operation
        %endif

        %rotate 4
    %endrep
%endmacro

%macro __seh64_image_rva 1
    ; NASM 3.x warns about the COFF image-relative relocation required here.
    %if __?NASM_VERSION_ID?__ >= 0x03020000
        [warning push]
        [warning -reloc-abs-dword]
    %elif __?NASM_VERSION_ID?__ >= 0x03010000
        [warning -reloc-abs-dword]
    %endif
    dd %1 wrt ..imagebase
    %if __?NASM_VERSION_ID?__ >= 0x03020000
        [warning pop]
    %elif __?NASM_VERSION_ID?__ >= 0x03010000
        [warning *reloc-abs-dword]
    %endif
%endmacro

%macro __seh64_open_proc 4
    %push seh64
    %xdefine %$name %1
    %xdefine %$begin %1
    %xdefine %$return_section __?SECT?__
    %xdefine %$ops
    %xdefine %$handler
    %xdefine %$handler_data
    %xdefine %$chain_parent
    %xdefine %$comdat_root %4
    %xdefine %$save_ranges

    %assign %$mode %2
    %assign %$comdat_selection %3
    %assign %$phase 0
    %assign %$prolog_done 0
    %assign %$op_count 0
    %assign %$slot_count 0
    %assign %$push_bytes 0
    %assign %$alloc_bytes 0
    %assign %$stack_delta 0
    %assign %$frame_reg 0
    %assign %$frame_offset 0
    %assign %$has_frame 0
    %assign %$has_saves 0
    %assign %$has_handler 0
    %assign %$flags 0
    %assign %$mach_frame 0
    %assign %$mach_frame_bytes 0
    %assign %$saved_gpr_mask 0
    %assign %$saved_xmm_mask 0
    %assign %$save_range_count 0

    %if %$comdat_selection = __SEH64_COMDAT_ROOT
        [section .text$seh64 code align=16 comdat=1:%1]
    %elif %$comdat_selection = __SEH64_COMDAT_ASSOCIATIVE
        [section .text$seh64 code align=16 comdat=5:%4]
    %endif

%1:
%endmacro

%imacro SEH_PROC 1
    %ifctx seh64
        __seh64_error SEH64-E010, nested SEH_PROC is not allowed
        %exitmacro
    %endif

    __seh64_open_proc %1, __SEH64_MODE_NORMAL, __SEH64_COMDAT_NONE, %1
%endmacro

%imacro SEH_PROC_COMDAT 1
    %ifctx seh64
        __seh64_error SEH64-E010, nested SEH_PROC_COMDAT is not allowed
        %exitmacro
    %endif

    __seh64_open_proc %1, __SEH64_MODE_NORMAL, __SEH64_COMDAT_ROOT, %1
%endmacro

%imacro SEH_CHAIN_PROC 2
    %ifctx seh64
        __seh64_error SEH64-E011, nested SEH_CHAIN_PROC is not allowed
        %exitmacro
    %endif
    %ifndef __seh64_profile_%[%2]_ready
        __seh64_error SEH64-E012, chained parent must be a preceding seh64 procedure in this object
        %exitmacro
    %endif

    %if %[]__seh64_profile_%[%2]_comdat
        __seh64_open_proc %1, __SEH64_MODE_CHAINED, __SEH64_COMDAT_ASSOCIATIVE, %[]__seh64_profile_%[%2]_comdat_root
    %else
        __seh64_open_proc %1, __SEH64_MODE_CHAINED, __SEH64_COMDAT_NONE, %1
    %endif
    %xdefine %$chain_parent %2
    %assign %$flags SEH64_CHAININFO
    %assign %$phase 2
    %assign %$push_bytes %[]__seh64_profile_%[%2]_push_bytes
    %assign %$alloc_bytes %[]__seh64_profile_%[%2]_alloc_bytes
    %assign %$stack_delta %[]__seh64_profile_%[%2]_stack_delta
    %assign %$frame_reg %[]__seh64_profile_%[%2]_frame_reg
    %assign %$frame_offset %[]__seh64_profile_%[%2]_frame_offset
    %assign %$has_frame %[]__seh64_profile_%[%2]_has_frame
    %assign %$mach_frame %[]__seh64_profile_%[%2]_mach_frame
    %assign %$mach_frame_bytes %[]__seh64_profile_%[%2]_mach_frame_bytes
    %assign %$saved_gpr_mask %[]__seh64_profile_%[%2]_saved_gpr_mask
    %assign %$saved_xmm_mask %[]__seh64_profile_%[%2]_saved_xmm_mask
    %assign %$save_range_count %[]__seh64_profile_%[%2]_save_range_count
    %xdefine %$save_ranges %[]__seh64_profile_%[%2]_save_ranges
%endmacro

%imacro SEH_PUSHREG 1
    %ifnctx seh64
        __seh64_error SEH64-E100, SEH_PUSHREG requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E101, SEH_PUSHREG %1 cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E102, chained unwind ranges cannot contain UWOP_PUSH_NONVOL
        %exitmacro
    %endif
    %if %$phase != 0
        __seh64_error SEH64-E103, nonvolatile pushes must precede stack allocation and saves
        %exitmacro
    %endif

    __seh64_nonvolatile_gpr %1
    %if %$reg_id < 0
        __seh64_error SEH64-E104, SEH_PUSHREG %1: register is not a Win64 nonvolatile GPR
        %exitmacro
    %endif
    %if (%$saved_gpr_mask & (1 << %$reg_id)) != 0
        __seh64_error SEH64-E105, SEH_PUSHREG %1: register is already saved in this unwind state
        %exitmacro
    %endif

    push %1
%%after:
    __seh64_record __SEH64_KIND_PUSH, %%after, %$reg_id, 0, 1
    %assign %$push_bytes %$push_bytes + 8
    %assign %$stack_delta %$stack_delta + 8
    %assign %$saved_gpr_mask %$saved_gpr_mask | (1 << %$reg_id)
%endmacro

%imacro SEH_ALLOCSTACK 1
    %ifnctx seh64
        __seh64_error SEH64-E110, SEH_ALLOCSTACK requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E111, SEH_ALLOCSTACK %1 cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E112, chained unwind ranges cannot allocate more stack
        %exitmacro
    %endif
    %if %$phase > 1
        __seh64_error SEH64-E113, stack allocation must precede frame setup and saves
        %exitmacro
    %endif

    %assign %$size (%1)
    %if %$size <= 0
        __seh64_error SEH64-E114, SEH_ALLOCSTACK %1: size must be positive
        %exitmacro
    %endif
    %if (%$size & 7) != 0
        __seh64_error SEH64-E115, SEH_ALLOCSTACK %1: size must be 8-byte aligned
        %exitmacro
    %endif
    %if %$size > 0xfffffff8
        __seh64_error SEH64-E116, SEH_ALLOCSTACK %1: size exceeds the Win64 v1 limit
        %exitmacro
    %endif

    %if %$size >= SEH64_STACK_PROBE_THRESHOLD
        %if SEH64_STACK_PROBE_EXTERNAL
            %ifndef __seh64_stack_probe_declared
                extern SEH64_STACK_PROBE
                %define __seh64_stack_probe_declared 1
            %endif
        %endif
        mov rax, %$size
        %if __?NASM_VERSION_ID?__ >= 0x03020000
            [warning push]
            [warning -reloc-rel-dword]
        %elif __?NASM_VERSION_ID?__ >= 0x03010000
            [warning -reloc-rel-dword]
        %endif
        call SEH64_STACK_PROBE
        %if __?NASM_VERSION_ID?__ >= 0x03020000
            [warning pop]
        %elif __?NASM_VERSION_ID?__ >= 0x03010000
            [warning *reloc-rel-dword]
        %endif
        sub rsp, rax
    %else
        sub rsp, %$size
    %endif
%%after:
    %if %$size <= 128
        %assign %$new_slots 1
    %elif %$size <= 0x7fff8
        %assign %$new_slots 2
    %else
        %assign %$new_slots 3
    %endif
    __seh64_record __SEH64_KIND_ALLOC, %%after, 0, %$size, %$new_slots
    %assign %$alloc_bytes %$alloc_bytes + %$size
    %assign %$stack_delta %$stack_delta + %$size
    %assign %$phase 1
%endmacro

%imacro SEH_SETFRAME 2
    %ifnctx seh64
        __seh64_error SEH64-E120, SEH_SETFRAME requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E121, SEH_SETFRAME %1, %2 cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E122, chained unwind ranges inherit their frame register
        %exitmacro
    %endif
    %if %$has_frame
        __seh64_error SEH64-E123, SEH_SETFRAME %1, %2: frame register is already set
        %exitmacro
    %endif
    %if %$has_saves
        __seh64_error SEH64-E124, frame register must be established before offset-based saves
        %exitmacro
    %endif

    __seh64_nonvolatile_gpr %1
    %if %$reg_id < 0
        __seh64_error SEH64-E125, SEH_SETFRAME %1, %2: register cannot be used as a Win64 frame register
        %exitmacro
    %endif
    %if (%$saved_gpr_mask & (1 << %$reg_id)) = 0
        __seh64_error SEH64-E126, SEH_SETFRAME %1, %2: frame register must be saved first
        %exitmacro
    %endif

    %assign %$offset (%2)
    %if (%$offset < 0) || (%$offset > 240)
        __seh64_error SEH64-E127, SEH_SETFRAME %1, %2: offset must be between 0 and 240
        %exitmacro
    %endif
    %if (%$offset & 15) != 0
        __seh64_error SEH64-E128, SEH_SETFRAME %1, %2: offset must be 16-byte aligned
        %exitmacro
    %endif
    %if %$offset > %$alloc_bytes
        __seh64_error SEH64-E129, SEH_SETFRAME %1, %2: offset exceeds the fixed stack allocation
        %exitmacro
    %endif
    %if (%$mach_frame = 0) && (((8 - %$stack_delta) & 15) != 0)
        __seh64_error SEH64-E130, SEH_SETFRAME %1, %2: RSP must be 16-byte aligned
        %exitmacro
    %endif

    %if %$offset = 0
        mov %1, rsp
    %else
        lea %1, [rsp + %$offset]
    %endif
%%after:
    __seh64_record __SEH64_KIND_SET_FRAME, %%after, 0, 0, 1
    %assign %$frame_reg %$reg_id
    %assign %$frame_offset %$offset
    %assign %$has_frame 1
    %assign %$phase 2
%endmacro

%imacro SEH_SAVEREG 2
    %ifnctx seh64
        __seh64_error SEH64-E140, SEH_SAVEREG requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E141, SEH_SAVEREG %1, %2 cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif

    __seh64_nonvolatile_gpr %1
    %if %$reg_id < 0
        __seh64_error SEH64-E142, SEH_SAVEREG %1, %2: register is not a Win64 nonvolatile GPR
        %exitmacro
    %endif
    %if (%$saved_gpr_mask & (1 << %$reg_id)) != 0
        __seh64_error SEH64-E143, SEH_SAVEREG %1, %2: register is already saved in this unwind state
        %exitmacro
    %endif

    %assign %$offset (%2)
    %if %$offset < 0
        __seh64_error SEH64-E144, SEH_SAVEREG %1, %2: offset cannot be negative
        %exitmacro
    %endif
    %if (%$offset & 7) != 0
        __seh64_error SEH64-E145, SEH_SAVEREG %1, %2: offset must be 8-byte aligned
        %exitmacro
    %endif
    %if %$offset > 0x7ffffff8
        __seh64_error SEH64-E146, SEH_SAVEREG %1, %2: offset exceeds a signed x86-64 displacement
        %exitmacro
    %endif

    __seh64_check_save_slot %$offset, 8
    %if %$save_slot_ok = 0
        __seh64_error SEH64-E147, SEH_SAVEREG %1, %2: slot overlaps pushed state, a return address, or a machine frame
        %exitmacro
    %endif
    %if %$save_slot_backed = 0
        __seh64_error SEH64-E148, SEH_SAVEREG %1, %2: slot is outside allocated stack and caller home space
        %exitmacro
    %endif

    __seh64_check_save_range %$offset, 8
    %if %$save_range_conflict
        __seh64_error SEH64-E149, SEH_SAVEREG %1, %2: slot overlaps another saved register
        %exitmacro
    %endif

    mov [rsp + %$offset], %1
%%after:
    %if %$offset <= 0x7fff8
        %assign %$new_slots 2
    %else
        %assign %$new_slots 3
    %endif
    __seh64_record __SEH64_KIND_SAVE_GPR, %%after, %$reg_id, %$offset, %$new_slots
    %assign %$has_saves 1
    %assign %$phase 2
    %assign %$saved_gpr_mask %$saved_gpr_mask | (1 << %$reg_id)
    __seh64_record_save_range %$offset, 8
%endmacro

%imacro SEH_SAVEXMM 2
    %ifnctx seh64
        __seh64_error SEH64-E160, SEH_SAVEXMM requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E161, SEH_SAVEXMM %1, %2 cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E162, chained shrink-wrap ranges support SEH_SAVEREG only
        %exitmacro
    %endif
    %if %$mach_frame
        __seh64_error SEH64-E163, XMM saves require a normal Win64 entry alignment contract
        %exitmacro
    %endif

    __seh64_nonvolatile_xmm %1
    %if %$reg_id < 0
        __seh64_error SEH64-E164, SEH_SAVEXMM %1, %2: register is not a Win64 nonvolatile XMM register
        %exitmacro
    %endif
    %if (%$saved_xmm_mask & (1 << %$reg_id)) != 0
        __seh64_error SEH64-E165, SEH_SAVEXMM %1, %2: register is already saved in this unwind state
        %exitmacro
    %endif

    %assign %$offset (%2)
    %if %$offset < 0
        __seh64_error SEH64-E166, SEH_SAVEXMM %1, %2: offset cannot be negative
        %exitmacro
    %endif
    %if (%$offset & 15) != 0
        __seh64_error SEH64-E167, SEH_SAVEXMM %1, %2: offset must be 16-byte aligned
        %exitmacro
    %endif
    %if %$offset > 0x7ffffff0
        __seh64_error SEH64-E168, SEH_SAVEXMM %1, %2: offset exceeds a signed x86-64 displacement
        %exitmacro
    %endif
    %if (((8 - %$stack_delta + %$offset) & 15) != 0)
        __seh64_error SEH64-E169, SEH_SAVEXMM %1, %2: effective address is not 16-byte aligned
        %exitmacro
    %endif

    __seh64_check_save_slot %$offset, 16
    %if %$save_slot_ok = 0
        __seh64_error SEH64-E170, SEH_SAVEXMM %1, %2: slot overlaps pushed state or a return address
        %exitmacro
    %endif
    %if %$save_slot_backed = 0
        __seh64_error SEH64-E171, SEH_SAVEXMM %1, %2: slot is outside allocated stack and caller home space
        %exitmacro
    %endif

    __seh64_check_save_range %$offset, 16
    %if %$save_range_conflict
        __seh64_error SEH64-E172, SEH_SAVEXMM %1, %2: slot overlaps another saved register
        %exitmacro
    %endif

    movdqa [rsp + %$offset], %1
%%after:
    %if %$offset <= 0xffff0
        %assign %$new_slots 2
    %else
        %assign %$new_slots 3
    %endif
    __seh64_record __SEH64_KIND_SAVE_XMM, %%after, %$reg_id, %$offset, %$new_slots
    %assign %$has_saves 1
    %assign %$phase 2
    %assign %$saved_xmm_mask %$saved_xmm_mask | (1 << %$reg_id)
    __seh64_record_save_range %$offset, 16
%endmacro

%imacro SEH_PUSHFRAME 0-1
    %ifnctx seh64
        __seh64_error SEH64-E180, SEH_PUSHFRAME requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E181, SEH_PUSHFRAME cannot appear after SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E182, chained unwind ranges cannot push a machine frame
        %exitmacro
    %endif
    %if %$op_count != 0
        __seh64_error SEH64-E183, SEH_PUSHFRAME must be the first unwind operation
        %exitmacro
    %endif
    %if ($ - %$begin) != 0
        __seh64_error SEH64-E184, SEH_PUSHFRAME must precede every emitted byte
        %exitmacro
    %endif

    %assign %$has_error_code 0
    %if %0 = 1
        %assign %$has_error_code (%1)
        %if (%$has_error_code != 0) && (%$has_error_code != 1)
            __seh64_error SEH64-E185, SEH_PUSHFRAME accepts only 0 or 1
            %exitmacro
        %endif
    %endif
%%after:
    __seh64_record __SEH64_KIND_MACH_FRAME, %%after, %$has_error_code, 0, 1
    %assign %$mach_frame 1
    %assign %$mach_frame_bytes 40 + (%$has_error_code * 8)
%endmacro

%imacro SEH_HANDLER 2-3
    %ifnctx seh64
        __seh64_error SEH64-E190, SEH_HANDLER requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E191, SEH_HANDLER must appear before SEH_ENDPROLOG
        %exitmacro
    %endif
    %if %$mode = __SEH64_MODE_CHAINED
        __seh64_error SEH64-E192, CHAININFO is mutually exclusive with handlers
        %exitmacro
    %endif
    %if %$has_handler
        __seh64_error SEH64-E193, exception handler is already set
        %exitmacro
    %endif

    %assign %$handler_flags (%2)
    %if (%$handler_flags <= 0) || ((%$handler_flags & ~3) != 0)
        __seh64_error SEH64-E194, handler flags must use SEH64_EHANDLER and/or SEH64_UHANDLER
        %exitmacro
    %endif

    %xdefine %$handler %1
    %assign %$flags %$handler_flags
    %assign %$has_handler 1
    %if %0 = 3
        %xdefine %$handler_data %3
    %endif
%endmacro

%imacro SEH_ENDPROLOG 0
    %ifnctx seh64
        __seh64_error SEH64-E200, SEH_ENDPROLOG requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done
        __seh64_error SEH64-E201, SEH_ENDPROLOG was already emitted
        %exitmacro
    %endif

%$prolog_end:
    %if ($ - %$begin) > 255
        __seh64_error SEH64-E202, Win64 SizeOfProlog exceeds 255 bytes
    %endif
    %if %$slot_count > 255
        __seh64_error SEH64-E203, Win64 CountOfCodes exceeds 255 slots
    %endif
    %if (%$mode = __SEH64_MODE_NORMAL) && (%$mach_frame = 0) && (%$stack_delta > 0)
        %if ((%$stack_delta & 15) != 8)
            __seh64_error SEH64-E204, RSP is not 16-byte aligned at the end of the prologue
        %endif
    %endif

    %assign %$prolog_done 1
%endmacro

%imacro SEH_ENDPROC 0
    %ifnctx seh64
        __seh64_error SEH64-E210, SEH_ENDPROC requires an active SEH_PROC
        %exitmacro
    %endif
    %if %$prolog_done = 0
        __seh64_error SEH64-E211, SEH_ENDPROC requires SEH_ENDPROLOG
        %exitmacro
    %endif

__seh64_end_%[%$name]:

    %if %$comdat_selection = __SEH64_COMDAT_NONE
        [section .xdata]
    %else
        [section .xdata$seh64 rdata align=4 comdat=5:%$comdat_root]
    %endif
    align 4
__seh64_unwind_%[%$name]:
    db 1 | (%$flags << 3)
    db %$prolog_end - %$begin
    db %$slot_count
    db (%$frame_offset & 0xf0) | %$frame_reg

    %if %$op_count > 0
        __seh64_emit_ops %$ops
    %endif
    %if (%$slot_count & 1) != 0
        dw 0
    %endif

    %if %$has_handler
        __seh64_image_rva %$handler
        %ifnempty %$handler_data
            %[%$handler_data]
        %endif
    %elif %$mode = __SEH64_MODE_CHAINED
        __seh64_image_rva %$chain_parent
        __seh64_image_rva __seh64_end_%[%$chain_parent]
        __seh64_image_rva __seh64_unwind_%[%$chain_parent]
    %endif

    %if %$comdat_selection = __SEH64_COMDAT_NONE
        [section .pdata]
    %else
        [section .pdata$seh64 rdata align=4 comdat=5:%$comdat_root]
    %endif
    align 4
    __seh64_image_rva %$begin
    __seh64_image_rva __seh64_end_%[%$name]
    __seh64_image_rva __seh64_unwind_%[%$name]

    %xdefine __seh64_profile_%[%$name]_ready 1
    %xdefine __seh64_profile_%[%$name]_push_bytes %$push_bytes
    %xdefine __seh64_profile_%[%$name]_alloc_bytes %$alloc_bytes
    %xdefine __seh64_profile_%[%$name]_stack_delta %$stack_delta
    %xdefine __seh64_profile_%[%$name]_frame_reg %$frame_reg
    %xdefine __seh64_profile_%[%$name]_frame_offset %$frame_offset
    %xdefine __seh64_profile_%[%$name]_has_frame %$has_frame
    %xdefine __seh64_profile_%[%$name]_mach_frame %$mach_frame
    %xdefine __seh64_profile_%[%$name]_mach_frame_bytes %$mach_frame_bytes
    %xdefine __seh64_profile_%[%$name]_saved_gpr_mask %$saved_gpr_mask
    %xdefine __seh64_profile_%[%$name]_saved_xmm_mask %$saved_xmm_mask
    %xdefine __seh64_profile_%[%$name]_save_range_count %$save_range_count
    %xdefine __seh64_profile_%[%$name]_save_ranges %$save_ranges
    %xdefine __seh64_profile_%[%$name]_comdat (%$comdat_selection != __SEH64_COMDAT_NONE)
    %xdefine __seh64_profile_%[%$name]_comdat_root %$comdat_root

    %$return_section
    %pop
%endmacro

%endif
