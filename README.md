# nasm-seh64

[![Unwind tests](https://github.com/xqzme69/nasm-seh64/actions/workflows/tests.yml/badge.svg)](https://github.com/xqzme69/nasm-seh64/actions/workflows/tests.yml)

Win64 unwind/SEH directives NASM never got.

NASM already knows how to write Win64 COFF, `.pdata`, `.xdata`, and
`wrt ..imagebase`. What it does not have is the useful MASM/Yasm part where a
prologue instruction and its unwind record stay together. I got tired of
writing a function once as code and then describing it again as a byte table,
so I made the include I wanted to use.

`seh64.inc` is a single-file macro library for NASM `-f win64`. Each prologue
macro emits the machine instruction and records the matching Win64 v1 unwind
operation at the same time. `SEH_ENDPROC` writes the finished `.xdata` and
`.pdata` records.

Drop `seh64.inc` into the include path; there is no generator, plugin, runtime
library, or post-link step. `SEH64_VERSION` is `0x000100` for release 0.1.0.
The include is the actual project. Most of the repository is tests because
unwind metadata that merely looks plausible is not good enough.

Grab the current release directly:

```powershell
Invoke-WebRequest https://github.com/xqzme69/nasm-seh64/releases/latest/download/seh64.inc -OutFile seh64.inc
```

```nasm
bits 64
default rel

%include "seh64.inc"

section .text
global parse_packet

SEH_PROC parse_packet
    SEH_PUSHREG rbp
    SEH_PUSHREG rbx
    SEH_ALLOCSTACK 0x48
    SEH_SETFRAME rbp, 0x20
    SEH_SAVEREG rsi, 0x30
    SEH_SAVEXMM xmm6, 0x10
    SEH_ENDPROLOG

    ; function body

    movdqa xmm6, [rsp + 0x10]
    mov rsi, [rsp + 0x30]
    add rsp, 0x48
    pop rbx
    pop rbp
    ret
SEH_ENDPROC
```

Assemble it normally:

```powershell
nasm -f win64 -Wall -Werror -I . -o parse_packet.obj parse_packet.asm
```

## Operations

| Macro | Win64 unwind operation |
| --- | --- |
| `SEH_PUSHREG reg` | `UWOP_PUSH_NONVOL` |
| `SEH_ALLOCSTACK size` | Smallest valid `UWOP_ALLOC_SMALL` or `UWOP_ALLOC_LARGE` form |
| `SEH_SETFRAME reg, offset` | `UWOP_SET_FPREG` |
| `SEH_SAVEREG reg, offset` | Smallest valid `UWOP_SAVE_NONVOL` form |
| `SEH_SAVEXMM reg, offset` | Smallest valid `UWOP_SAVE_XMM128` form |
| `SEH_PUSHFRAME [0 or 1]` | `UWOP_PUSH_MACHFRAME` metadata; no instruction is emitted |
| `SEH_HANDLER symbol, flags[, data_macro]` | `UNW_FLAG_EHANDLER` and/or `UNW_FLAG_UHANDLER` |
| `SEH_CHAIN_PROC child, parent` | `UNW_FLAG_CHAININFO` for shrink-wrapped GPR saves |
| `SEH_PROC_COMDAT name` | Function-level COMDAT with associative unwind metadata |

There is no separate "auto" mode. Compact encoding selection is the default.
The allocation boundaries are `128`, `0x7fff8`, and `0x80000`; GPR and XMM
saves switch to their far forms at `0x80000` and `0x100000` respectively.

## COMDAT and dead stripping

Use `SEH_PROC_COMDAT` for a function that should participate in function-level
linking:

```nasm
section .text
global parse_optional_chunk

SEH_PROC_COMDAT parse_optional_chunk
    SEH_ALLOCSTACK 0x28
    SEH_ENDPROLOG
    ; ...
    add rsp, 0x28
    ret
SEH_ENDPROC
```

The macro places the function in a `.text$seh64` root COMDAT. Its
`.xdata$seh64` and `.pdata$seh64` sections use
`IMAGE_COMDAT_SELECT_ASSOCIATIVE`, so `/OPT:REF` discards the function and both
metadata records as one unit. A `SEH_CHAIN_PROC` whose parent is COMDAT inherits
the same root automatically, including multi-level chains.

Plain `SEH_PROC` keeps the original shared-section behavior. COMDAT is explicit
because `SEH_PROC_COMDAT` temporarily switches the code section and then
returns to the caller's section at `SEH_ENDPROC`.

NASM 3.x reports unresolved or cross-section `call`/`jmp` relocations under the
generic `reloc-rel-dword` category when `-Wall` is enabled. COFF REL32 is the
expected encoding for direct calls to externals and between COMDAT functions.
If `-Werror` is also enabled, disable that warning locally around those
branches; do not silence the rest of the file.

## Handlers

The optional third argument to `SEH_HANDLER` names a zero-argument NASM macro.
It is expanded directly after the handler RVA, where language-specific data
belongs.

```nasm
%macro filter_data 0
    dd 0x53454836
%endmacro

SEH_PROC guarded_range
    SEH_ALLOCSTACK 0x28
    SEH_HANDLER my_handler, SEH64_EHANDLER, filter_data
    SEH_ENDPROLOG
    ; ...
SEH_ENDPROC
```

`SEH64_EHANDLER` and `SEH64_UHANDLER` may be combined. `CHAININFO` is mutually
exclusive with both, as required by the format.

## Chained ranges

The primary range must appear earlier in the same object. A chained range
inherits its frame register, fixed allocation, machine-frame layout, and
saved-register state. It may add `SEH_SAVEREG` operations only; Win64 does not
permit another push or fixed allocation in this shrink-wrap form.

```nasm
SEH_CHAIN_PROC parse_packet_cold, parse_packet
    SEH_SAVEREG r12, 0x08
    SEH_ENDPROLOG
    ; ...
SEH_ENDPROC
```

Chains may point to another chained range. Duplicate saves are rejected across
the full inherited state.

## Stack probing

Allocations of 4096 bytes or more use the standard `__chkstk` sequence:

```nasm
mov rax, size
call __chkstk
sub rsp, rax
```

The symbol and threshold are configurable before including the file:

```nasm
%define SEH64_STACK_PROBE my_stack_probe
%define SEH64_STACK_PROBE_THRESHOLD 8192
%define SEH64_STACK_PROBE_EXTERNAL 0
%include "seh64.inc"
```

Set `SEH64_STACK_PROBE_EXTERNAL` to `0` when the probe symbol is defined in the
same source instead of being external.

## Checks

The assembler rejects invalid state while it still has useful source context:

- volatile or duplicate register saves;
- unaligned or out-of-range stack operations;
- XMM saves whose effective address is not 16-byte aligned;
- saves outside the fixed allocation and 32-byte caller home space;
- GPR and XMM save slots that overlap each other, including inherited chains;
- saves overlapping pushed state, the return address, or a machine frame;
- a frame register that was not saved first, or a second frame register;
- illegal operation ordering and operations after `SEH_ENDPROLOG`;
- prologues or unwind-code arrays that exceed their one-byte limits;
- incompatible handlers and chained unwind data;
- a chained parent that cannot be validated in the current object.

Diagnostics have stable IDs and include the active function plus the rejected
macro invocation. For example:

```text
seh64: parse_packet: SEH64-E169: SEH_SAVEXMM xmm6, 0x18: effective address is not 16-byte aligned
```

## Contract

- Target: x86-64 COFF/PE, NASM `-f win64`, Win64 unwind version 1.
- Tested assemblers: NASM 2.16.01, 3.01, and 3.02. The intended minimum is
  NASM 2.16; future assembler releases still need their own test run.
- Use the `SEH_*` macros for every prologue instruction that changes `RSP`, a
  nonvolatile register, or unwind state. The preprocessor cannot inspect an
  unrelated hand-written instruction.
- `SEH_PUSHFRAME` describes a hardware-created machine frame. It deliberately
  emits no push instruction and must be the first unwind operation.
- The function body and legal Win64 epilog remain ordinary assembly and are the
  caller's responsibility.
- APX unwind v2/v3 is outside this library's v1 contract.

## Tests

```powershell
pwsh -File .\tests\run.ps1
```

The full gate assembles positive and negative fixtures with `-Wall -Werror`,
decodes every object with `llvm-readobj`, compares the same prologue against
Yasm and MASM, and validates generated prologues against an independent code
offset and unwind-operation model. COMDAT tests link with `/OPT:REF` through
both `link.exe` and `lld-link` and require dead code and its unwind metadata to
disappear together.

The runtime harness uses `RtlVirtualUnwind` at every operation boundary of its
mixed GPR/XMM/frame-register prologue and also exercises normal Windows
exception dispatch. It handles a software exception, an access violation, and
integer divide-by-zero, then unwinds through two NASM frames with real
EHANDLER/UHANDLER calls. Handler data, call order, machine frames, chained
records, and nonvolatile GPR/XMM state are checked in the linked executable.

Use `-StaticOnly` on a machine without the MSVC x64 tools:

```powershell
pwsh -File .\tests\run.ps1 -StaticOnly
```

The default randomized pass uses 512 cases and a fixed seed. Larger or new-seed
runs are explicit and reproducible:

```powershell
pwsh -File .\tests\run.ps1 -RandomCases 10000 -RandomSeed 0x5e6402
```

GitHub Actions keeps the release matrix on NASM 2.16.01, 3.01, and 3.02. A
scheduled Linux job builds the current `netwide-assembler/nasm` master through
its own `autogen.sh`/`configure` path and runs the 10,000-case static gate. The
nightly seed changes with the UTC date and is written to the job summary, so a
failure can be replayed locally.

Verified on 2026-08-14:

| Component | Coverage |
| --- | --- |
| NASM 2.16.01 | Full static, differential, runtime, and dual-linker gate |
| NASM 3.01 | Full static, differential, runtime, and dual-linker gate |
| NASM 3.02 | Full static, differential, runtime, and dual-linker gate |
| NASM master | Nightly GNU source build and 10,000-case static gate |
| Yasm 1.3.0 | Decoded differential reference |
| MASM 14.51 | Decoded differential reference |
| `link.exe` and `lld-link` | Executed `RtlVirtualUnwind` harness |

Tool paths may be supplied with `-Nasm`, `-Yasm`, `-LlvmReadObj`, and
`-VcVars64`. Missing optional reference tools are reported as `SKIP`; the
runtime toolchain is required unless `-StaticOnly` is used.

## Sources

- [Microsoft x64 exception handling](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64)
- [Microsoft x64 prolog and epilog rules](https://learn.microsoft.com/en-us/cpp/build/prolog-and-epilog)
- [NASM Win64 object format](https://www.nasm.us/doc/nasm09.html)
- [Microsoft PE/COFF COMDAT format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#comdat-sections-object-only)
- [Yasm Win64 exception handling](https://www.tortall.net/projects/yasm/manual/html/objfmt-win64-exception.html)

## License

MIT. See [LICENSE](LICENSE).
