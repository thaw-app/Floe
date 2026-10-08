#ifndef FEND_CORE_H
#define FEND_CORE_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque calculation context maintaining variables and session state.
typedef struct FendContext FendContext;

/// Create a new calculation context. Returns NULL on failure.
FendContext* _Nullable fend_context_new(void);

/// Free a calculation context.
void fend_context_free(FendContext* _Nullable ctx);

/// Reset variables and state in the given context.
void fend_context_reset(FendContext* _Nonnull ctx);

/// Give the context its exchange rates: `count` currency codes and, beside each, how much of it one unit of
/// the base currency buys. The base currency is in the list with a rate of 1. A count of 0 takes them away.
void fend_context_set_exchange_rates(FendContext* _Nonnull ctx, const char* _Nullable const* _Nullable codes, const double* _Nullable rates, size_t count);

/// Serialize variables from the context into a buffer.
/// If `buffer` is NULL, returns the number of bytes required.
/// Returns negative value on failure.
int64_t fend_context_serialize_variables(
    FendContext* _Nonnull ctx,
    uint8_t* _Nullable buffer,
    size_t buffer_len
);

/// Deserialize variables into the context from the given byte buffer.
/// Returns 0 on success, or -1 on failure.
int32_t fend_context_deserialize_variables(
    FendContext* _Nonnull ctx,
    const uint8_t* _Nonnull bytes,
    size_t len
);

/// Opaque evaluation result.
typedef struct FendResult FendResult;

/// Evaluate a query string in the given context, mutating variables if assigned.
FendResult* _Nullable fend_evaluate(
    FendContext* _Nonnull ctx,
    const char* _Nonnull query
);

/// Evaluate a query string in the given context as a non-mutating preview.
/// Incomplete or syntax-invalid queries return an empty result without failing.
FendResult* _Nullable fend_evaluate_preview(
    FendContext* _Nonnull ctx,
    const char* _Nonnull query
);

/// Free an evaluation result.
void fend_result_free(FendResult* _Nullable result);

/// Returns true if the evaluation completed successfully.
bool fend_result_is_ok(const FendResult* _Nonnull result);

/// Returns true if the result produced no visible output (e.g. empty expression or quiet assignment).
bool fend_result_is_empty(const FendResult* _Nonnull result);

/// Returns the primary text result if successful, or NULL.
const char* _Nullable fend_result_get_value(const FendResult* _Nonnull result);

/// Returns the error message string if evaluation failed, or NULL.
const char* _Nullable fend_result_get_error(const FendResult* _Nonnull result);

/// Classification of syntax tokens in evaluated fend expressions.
typedef enum FendSpanKind {
    FEND_SPAN_NUMBER = 0,
    FEND_SPAN_BUILT_IN_FUNCTION = 1,
    FEND_SPAN_KEYWORD = 2,
    FEND_SPAN_STRING = 3,
    FEND_SPAN_DATE = 4,
    FEND_SPAN_WHITESPACE = 5,
    FEND_SPAN_IDENT = 6,
    FEND_SPAN_BOOLEAN = 7,
    FEND_SPAN_OTHER = 8,
} FendSpanKind;

/// Returns the number of spans in the result.
size_t fend_result_get_span_count(const FendResult* _Nonnull result);

/// Returns the text of the span at `index`, or NULL if index is out of bounds.
const char* _Nullable fend_result_get_span_string(const FendResult* _Nonnull result, size_t index);

/// Returns the kind of the span at `index`, or FEND_SPAN_OTHER if index is out of bounds.
FendSpanKind fend_result_get_span_kind(const FendResult* _Nonnull result, size_t index);

/// Opaque completions container.
typedef struct FendCompletions FendCompletions;

/// Get autocompletions for a prefix.
FendCompletions* _Nullable fend_get_completions(const char* _Nonnull prefix);

/// Free completions container.
void fend_completions_free(FendCompletions* _Nullable completions);

/// Returns the number of completion suggestions.
size_t fend_completions_get_count(const FendCompletions* _Nonnull completions);

/// Returns the replacement start index in the prefix.
size_t fend_completions_get_start_index(const FendCompletions* _Nonnull completions);

/// Returns the completion display text at index, or NULL.
const char* _Nullable fend_completions_get_item(const FendCompletions* _Nonnull completions, size_t index);

/// Returns the underlying fend-core library version string.
const char* _Nonnull fend_get_version(void);

#ifdef __cplusplus
}
#endif

#endif /* FEND_CORE_H */
