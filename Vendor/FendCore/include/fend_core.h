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

/// The names of the files under one folder, held in memory. Every function may be called from any thread,
/// and every string is UTF-8.
typedef struct FloeFileIndex FloeFileIndex;

/// Create an empty index. Returns NULL on failure.
FloeFileIndex* _Nullable floe_index_new(void);

/// Free an index. No other call on it may be running.
void floe_index_free(FloeFileIndex* _Nullable index);

/// Walk `root` and replace what the index holds. Folders named in `excluded_names` are left out, as is every
/// name that starts with a dot; a folder whose name ends in one of `package_suffixes` is listed and not entered.
/// Blocks until the walk is done. Returns the number of entries, or -1 on failure.
int64_t floe_index_build(
    const FloeFileIndex* _Nonnull index,
    const char* _Nonnull root,
    const char* _Nullable const* _Nullable excluded_names,
    size_t excluded_name_count,
    const char* _Nullable const* _Nullable package_suffixes,
    size_t package_suffix_count
);

/// Bring one folder in line with the disk: what is directly in it, or with `recursive` everything under it.
void floe_index_rescan(const FloeFileIndex* _Nonnull index, const char* _Nonnull path, bool recursive);

/// The best `limit` matches for `query`, as one block of `*length` bytes to free with `floe_index_block_free`.
/// Numbers are little-endian uint32 and not aligned: the count of hits, then for each hit its score, one byte
/// that is 1 for a folder, the length of its path, the path, the count of matched characters in the file name
/// and their offsets. Returns NULL on failure.
uint8_t* _Nullable floe_index_search(
    const FloeFileIndex* _Nonnull index,
    const char* _Nonnull query,
    size_t limit,
    size_t* _Nonnull length
);

/// Free a block that `floe_index_search` returned.
void floe_index_block_free(uint8_t* _Nullable block, size_t length);

/// The number of entries in the index.
size_t floe_index_count(const FloeFileIndex* _Nullable index);

/// Roughly how much memory the index holds, in bytes.
size_t floe_index_byte_size(const FloeFileIndex* _Nullable index);

#ifdef __cplusplus
}
#endif

#endif /* FEND_CORE_H */
