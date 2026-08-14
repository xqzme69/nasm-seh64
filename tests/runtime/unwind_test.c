#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern int seh64_runtime_call_probe(void);
extern int seh64_runtime_raise_dispatch(void);
extern int seh64_runtime_av_dispatch(void);
extern int seh64_runtime_divide_dispatch(void);
extern int seh64_runtime_unwind_probe(void);
extern void seh64_runtime_unwind_outer(void);

extern unsigned char seh64_runtime_target[];
extern unsigned char seh64_runtime_after_push_rbp[];
extern unsigned char seh64_runtime_after_push_rbx[];
extern unsigned char seh64_runtime_after_alloc[];
extern unsigned char seh64_runtime_after_setframe[];
extern unsigned char seh64_runtime_after_save_rsi[];
extern unsigned char seh64_runtime_after_save_xmm6[];
extern unsigned char seh64_runtime_body[];

extern unsigned char seh64_runtime_handler_body[];
extern unsigned char seh64_runtime_handler[];
extern unsigned char seh64_runtime_chain_body[];
extern unsigned char seh64_runtime_machframe_body[];
extern unsigned char seh64_runtime_machframe_error_body[];
extern unsigned char seh64_runtime_return_marker[];
extern unsigned char seh64_runtime_av_resume[];
extern unsigned char seh64_runtime_divide_resume[];

enum {
    TARGET_STACK_SIZE = 0x48,
    HANDLER_STACK_SIZE = 0x28,
    CHAIN_STACK_SIZE = 0x20,
    HANDLER_PAYLOAD = 0x53454836
};

#define RUNTIME_EXCEPTION_CODE ((DWORD)0xe0646401u)
#define RAISE_PAYLOAD ((ULONG)0x45534952u)
#define AV_PAYLOAD ((ULONG)0x20205641u)
#define DIVIDE_PAYLOAD ((ULONG)0x20564944u)
#define UNWIND_INNER_PAYLOAD ((ULONG)0x524e4e49u)
#define UNWIND_OUTER_PAYLOAD ((ULONG)0x5254554fu)

enum {
    DISPATCH_SEARCH_COUNT = 3,
    DISPATCH_UNWIND_COUNT = 2
};

static const ULONG64 OLD_RBP = 0x1020304050607080ULL;
static const ULONG64 OLD_RBX = 0x1122334455667788ULL;
static const ULONG64 OLD_RSI = 0x8877665544332211ULL;
static const ULONG64 OLD_R12 = 0x0f1e2d3c4b5a6978ULL;
static const ULONG64 XMM6_LOW = 0x0123456789abcdefULL;
static const ULONG64 XMM6_HIGH = 0xfedcba9876543210ULL;

static DWORD dispatch_search_codes[DISPATCH_SEARCH_COUNT];
static ULONG dispatch_search_payloads[DISPATCH_SEARCH_COUNT];
static ULONG dispatch_unwind_payloads[DISPATCH_UNWIND_COUNT];
static size_t dispatch_search_seen;
static size_t dispatch_unwind_seen;
static int dispatch_failed;

typedef struct target_checkpoint {
    const char *name;
    const unsigned char *pc;
    unsigned int operations;
    int body;
} target_checkpoint;

static ULONG64 ptr64(const void *pointer)
{
    return (ULONG64)(uintptr_t)pointer;
}

EXCEPTION_DISPOSITION seh64_runtime_dispatch_handler(
    PEXCEPTION_RECORD record,
    ULONG64 establisher_frame,
    PCONTEXT context,
    PDISPATCHER_CONTEXT dispatcher)
{
    ULONG payload;

    (void)establisher_frame;
    if (record == NULL || context == NULL || dispatcher == NULL || dispatcher->HandlerData == NULL) {
        dispatch_failed = 1;
        return ExceptionContinueSearch;
    }

    payload = *(const ULONG *)dispatcher->HandlerData;
    if ((record->ExceptionFlags & (EXCEPTION_UNWINDING | EXCEPTION_EXIT_UNWIND)) != 0) {
        if (dispatch_unwind_seen < DISPATCH_UNWIND_COUNT) {
            dispatch_unwind_payloads[dispatch_unwind_seen] = payload;
        }
        else {
            dispatch_failed = 1;
        }
        dispatch_unwind_seen++;
        return ExceptionContinueSearch;
    }

    if (dispatch_search_seen < DISPATCH_SEARCH_COUNT) {
        dispatch_search_codes[dispatch_search_seen] = record->ExceptionCode;
        dispatch_search_payloads[dispatch_search_seen] = payload;
    }
    else {
        dispatch_failed = 1;
    }
    dispatch_search_seen++;

    switch (payload) {
    case RAISE_PAYLOAD:
        if (record->ExceptionCode != RUNTIME_EXCEPTION_CODE) {
            dispatch_failed = 1;
            return ExceptionContinueSearch;
        }
        return ExceptionContinueExecution;

    case AV_PAYLOAD:
        if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) {
            dispatch_failed = 1;
            return ExceptionContinueSearch;
        }
        context->Rip = ptr64(seh64_runtime_av_resume);
        return ExceptionContinueExecution;

    case DIVIDE_PAYLOAD:
        if (record->ExceptionCode != EXCEPTION_INT_DIVIDE_BY_ZERO) {
            dispatch_failed = 1;
            return ExceptionContinueSearch;
        }
        context->Rip = ptr64(seh64_runtime_divide_resume);
        return ExceptionContinueExecution;

    default:
        dispatch_failed = 1;
        return ExceptionContinueSearch;
    }
}

int seh64_runtime_catch_unwind(void)
{
    __try {
        seh64_runtime_unwind_outer();
    }
    __except (GetExceptionCode() == RUNTIME_EXCEPTION_CODE ?
        EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH) {
        return 1;
    }

    return 0;
}

static int check_exception_dispatch(void)
{
    static const DWORD expected_codes[DISPATCH_SEARCH_COUNT] = {
        RUNTIME_EXCEPTION_CODE,
        EXCEPTION_ACCESS_VIOLATION,
        EXCEPTION_INT_DIVIDE_BY_ZERO
    };
    static const ULONG expected_search[DISPATCH_SEARCH_COUNT] = {
        RAISE_PAYLOAD,
        AV_PAYLOAD,
        DIVIDE_PAYLOAD
    };
    static const ULONG expected_unwind[DISPATCH_UNWIND_COUNT] = {
        UNWIND_INNER_PAYLOAD,
        UNWIND_OUTER_PAYLOAD
    };
    size_t index;

    memset(dispatch_search_codes, 0, sizeof(dispatch_search_codes));
    memset(dispatch_search_payloads, 0, sizeof(dispatch_search_payloads));
    memset(dispatch_unwind_payloads, 0, sizeof(dispatch_unwind_payloads));
    dispatch_search_seen = 0;
    dispatch_unwind_seen = 0;
    dispatch_failed = 0;

    if (!seh64_runtime_raise_dispatch() ||
        !seh64_runtime_av_dispatch() ||
        !seh64_runtime_divide_dispatch() ||
        !seh64_runtime_unwind_probe()) {
        puts("FAIL dispatch: exception path did not resume or preserve nonvolatile state");
        return 0;
    }

    if (dispatch_failed ||
        dispatch_search_seen != DISPATCH_SEARCH_COUNT ||
        dispatch_unwind_seen != DISPATCH_UNWIND_COUNT) {
        printf("FAIL dispatch: failed=%d search=%zu unwind=%zu\n",
            dispatch_failed,
            dispatch_search_seen,
            dispatch_unwind_seen);
        return 0;
    }

    for (index = 0; index < DISPATCH_SEARCH_COUNT; ++index) {
        if (dispatch_search_codes[index] != expected_codes[index] ||
            dispatch_search_payloads[index] != expected_search[index]) {
            printf("FAIL dispatch/search/%zu: code=%lx payload=%lx\n",
                index,
                dispatch_search_codes[index],
                dispatch_search_payloads[index]);
            return 0;
        }
    }

    for (index = 0; index < DISPATCH_UNWIND_COUNT; ++index) {
        if (dispatch_unwind_payloads[index] != expected_unwind[index]) {
            printf("FAIL dispatch/unwind/%zu: payload=%lx\n",
                index,
                dispatch_unwind_payloads[index]);
            return 0;
        }
    }

    return 1;
}

static ULONG64 prepare_stack(unsigned char *storage, size_t size)
{
    ULONG64 middle;

    memset(storage, 0, size);
    middle = ptr64(storage + size / 2);
    return (middle & ~0xfULL) + 8;
}

static void write_u64(ULONG64 address, ULONG64 value)
{
    memcpy((void *)(uintptr_t)address, &value, sizeof(value));
}

static void write_m128(ULONG64 address, ULONG64 low, ULONG64 high)
{
    M128A value;

    value.Low = low;
    value.High = (LONGLONG)high;
    memcpy((void *)(uintptr_t)address, &value, sizeof(value));
}

static int equal_m128(const M128A *value, ULONG64 low, ULONG64 high)
{
    return value->Low == low && (ULONG64)value->High == high;
}

static int lookup_entry(ULONG64 control_pc, PRUNTIME_FUNCTION *entry, ULONG64 *image_base)
{
    *entry = RtlLookupFunctionEntry(control_pc, image_base, NULL);
    if (*entry == NULL) {
        printf("FAIL lookup: no RUNTIME_FUNCTION for %p\n", (void *)(uintptr_t)control_pc);
        return 0;
    }
    return 1;
}

static int check_target_checkpoint(const target_checkpoint *checkpoint)
{
    __declspec(align(16)) unsigned char storage[512];
    CONTEXT context;
    PRUNTIME_FUNCTION entry;
    ULONG64 image_base;
    ULONG64 establisher_frame = 0;
    ULONG64 entry_rsp;
    ULONG64 current_rsp;
    PVOID handler_data = NULL;
    PEXCEPTION_ROUTINE handler;

    entry_rsp = prepare_stack(storage, sizeof(storage));
    current_rsp = entry_rsp;
    write_u64(entry_rsp, ptr64(seh64_runtime_return_marker));

    memset(&context, 0, sizeof(context));
    context.ContextFlags = CONTEXT_ALL;
    context.Rip = ptr64(checkpoint->pc);
    context.Rbp = OLD_RBP;
    context.Rbx = OLD_RBX;
    context.Rsi = OLD_RSI;
    context.Xmm6.Low = XMM6_LOW;
    context.Xmm6.High = (LONGLONG)XMM6_HIGH;

    if (checkpoint->operations >= 1) {
        current_rsp -= 8;
        write_u64(current_rsp, OLD_RBP);
    }
    if (checkpoint->operations >= 2) {
        current_rsp -= 8;
        write_u64(current_rsp, OLD_RBX);
    }
    if (checkpoint->operations >= 3) {
        current_rsp -= TARGET_STACK_SIZE;
    }
    if (checkpoint->operations >= 4) {
        context.Rbp = current_rsp + 0x20;
    }
    if (checkpoint->operations >= 5) {
        write_u64(current_rsp + 0x30, OLD_RSI);
    }
    if (checkpoint->operations >= 6) {
        write_m128(current_rsp + 0x10, XMM6_LOW, XMM6_HIGH);
    }
    if (checkpoint->body) {
        context.Rbx = 0xaaaaaaaaaaaaaaaaULL;
        context.Rsi = 0xbbbbbbbbbbbbbbbbULL;
        context.Xmm6.Low = ~XMM6_LOW;
        context.Xmm6.High = (LONGLONG)~XMM6_HIGH;
    }
    context.Rsp = current_rsp;

    if (!lookup_entry(context.Rip, &entry, &image_base)) {
        return 0;
    }

    handler = RtlVirtualUnwind(
        UNW_FLAG_NHANDLER,
        image_base,
        context.Rip,
        entry,
        &context,
        &handler_data,
        &establisher_frame,
        NULL);

    if (handler != NULL || handler_data != NULL ||
        context.Rip != ptr64(seh64_runtime_return_marker) ||
        context.Rsp != entry_rsp + 8 ||
        context.Rbp != OLD_RBP ||
        context.Rbx != OLD_RBX ||
        context.Rsi != OLD_RSI ||
        !equal_m128(&context.Xmm6, XMM6_LOW, XMM6_HIGH)) {
        printf("FAIL target/%s: rip=%llx rsp=%llx rbp=%llx rbx=%llx rsi=%llx\n",
            checkpoint->name,
            context.Rip,
            context.Rsp,
            context.Rbp,
            context.Rbx,
            context.Rsi);
        return 0;
    }

    return 1;
}

static int check_handler(void)
{
    __declspec(align(16)) unsigned char storage[256];
    CONTEXT context;
    PRUNTIME_FUNCTION entry;
    ULONG64 image_base;
    ULONG64 establisher_frame = 0;
    ULONG64 entry_rsp;
    PVOID handler_data = NULL;
    PEXCEPTION_ROUTINE handler;

    entry_rsp = prepare_stack(storage, sizeof(storage));
    write_u64(entry_rsp, ptr64(seh64_runtime_return_marker));
    memset(&context, 0, sizeof(context));
    context.ContextFlags = CONTEXT_ALL;
    context.Rip = ptr64(seh64_runtime_handler_body);
    context.Rsp = entry_rsp - HANDLER_STACK_SIZE;

    if (!lookup_entry(context.Rip, &entry, &image_base)) {
        return 0;
    }

    handler = RtlVirtualUnwind(
        UNW_FLAG_EHANDLER,
        image_base,
        context.Rip,
        entry,
        &context,
        &handler_data,
        &establisher_frame,
        NULL);

    if ((void *)handler != (void *)seh64_runtime_handler ||
        handler_data == NULL ||
        *(const ULONG *)handler_data != HANDLER_PAYLOAD ||
        context.Rip != ptr64(seh64_runtime_return_marker) ||
        context.Rsp != entry_rsp + 8) {
        printf("FAIL handler: handler=%p data=%p rip=%llx rsp=%llx\n",
            (void *)handler,
            handler_data,
            context.Rip,
            context.Rsp);
        return 0;
    }

    return 1;
}

static int check_chain(void)
{
    __declspec(align(16)) unsigned char storage[256];
    CONTEXT context;
    PRUNTIME_FUNCTION entry;
    ULONG64 image_base;
    ULONG64 establisher_frame = 0;
    ULONG64 entry_rsp;
    ULONG64 current_rsp;
    PVOID handler_data = NULL;

    entry_rsp = prepare_stack(storage, sizeof(storage));
    write_u64(entry_rsp, ptr64(seh64_runtime_return_marker));
    write_u64(entry_rsp - 8, OLD_RBP);
    current_rsp = entry_rsp - 8 - CHAIN_STACK_SIZE;
    write_u64(current_rsp + 0x10, OLD_R12);

    memset(&context, 0, sizeof(context));
    context.ContextFlags = CONTEXT_ALL;
    context.Rip = ptr64(seh64_runtime_chain_body);
    context.Rsp = current_rsp;
    context.Rbp = current_rsp;
    context.R12 = 0xccccccccccccccccULL;

    if (!lookup_entry(context.Rip, &entry, &image_base)) {
        return 0;
    }

    if (RtlVirtualUnwind(
            UNW_FLAG_NHANDLER,
            image_base,
            context.Rip,
            entry,
            &context,
            &handler_data,
            &establisher_frame,
            NULL) != NULL ||
        context.Rip != ptr64(seh64_runtime_return_marker) ||
        context.Rsp != entry_rsp + 8 ||
        context.Rbp != OLD_RBP ||
        context.R12 != OLD_R12) {
        printf("FAIL chain: rip=%llx rsp=%llx rbp=%llx r12=%llx\n",
            context.Rip,
            context.Rsp,
            context.Rbp,
            context.R12);
        return 0;
    }

    return 1;
}

static int check_machine_frame(const unsigned char *pc, int has_error_code)
{
    __declspec(align(16)) unsigned char storage[256];
    CONTEXT context;
    PRUNTIME_FUNCTION entry;
    ULONG64 image_base;
    ULONG64 establisher_frame = 0;
    ULONG64 frame_rsp;
    ULONG64 old_rsp;
    ULONG64 slot;
    PVOID handler_data = NULL;

    frame_rsp = prepare_stack(storage, sizeof(storage)) - 64;
    old_rsp = frame_rsp + 96;
    slot = frame_rsp;
    if (has_error_code) {
        write_u64(slot, 0xdead);
        slot += 8;
    }
    write_u64(slot, ptr64(seh64_runtime_return_marker));
    write_u64(slot + 8, 0x33);
    write_u64(slot + 16, 0x202);
    write_u64(slot + 24, old_rsp);
    write_u64(slot + 32, 0x2b);

    memset(&context, 0, sizeof(context));
    context.ContextFlags = CONTEXT_ALL;
    context.Rip = ptr64(pc);
    context.Rsp = frame_rsp;

    if (!lookup_entry(context.Rip, &entry, &image_base)) {
        return 0;
    }

    if (RtlVirtualUnwind(
            UNW_FLAG_NHANDLER,
            image_base,
            context.Rip,
            entry,
            &context,
            &handler_data,
            &establisher_frame,
            NULL) != NULL ||
        context.Rip != ptr64(seh64_runtime_return_marker) ||
        context.Rsp != old_rsp) {
        printf("FAIL machframe/%d: rip=%llx rsp=%llx\n",
            has_error_code,
            context.Rip,
            context.Rsp);
        return 0;
    }

    return 1;
}

int main(void)
{
    static const target_checkpoint checkpoints[] = {
        { "entry", seh64_runtime_target, 0, 0 },
        { "push-rbp", seh64_runtime_after_push_rbp, 1, 0 },
        { "push-rbx", seh64_runtime_after_push_rbx, 2, 0 },
        { "alloc", seh64_runtime_after_alloc, 3, 0 },
        { "setframe", seh64_runtime_after_setframe, 4, 0 },
        { "save-rsi", seh64_runtime_after_save_rsi, 5, 0 },
        { "save-xmm6", seh64_runtime_after_save_xmm6, 6, 0 },
        { "body", seh64_runtime_body, 6, 1 }
    };
    size_t index;

    if (!seh64_runtime_call_probe()) {
        puts("FAIL execution: nonvolatile state was not preserved");
        return 1;
    }
    if (!check_exception_dispatch()) {
        return 1;
    }

    for (index = 0; index < sizeof(checkpoints) / sizeof(checkpoints[0]); ++index) {
        if (!check_target_checkpoint(&checkpoints[index])) {
            return 1;
        }
    }

    if (!check_handler() ||
        !check_chain() ||
        !check_machine_frame(seh64_runtime_machframe_body, 0) ||
        !check_machine_frame(seh64_runtime_machframe_error_body, 1)) {
        return 1;
    }

    printf("PASS runtime: ABI execution, %zu virtual-unwind checkpoints, 3 dispatched exceptions, 2 unwind handlers, chain, 2 machine frames\n",
        sizeof(checkpoints) / sizeof(checkpoints[0]));
    return 0;
}
