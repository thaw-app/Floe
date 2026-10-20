//! fend's calculator: a context that keeps variables and exchange rates, and the answer to one query with its spans.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::catch_unwind;
use std::ptr;
use std::slice;
use std::sync::Arc;
use std::time::{Duration, Instant};
use fend_core::{Context, ExchangeRateFnV2, ExchangeRateFnV2Options, Interrupt};


/// How long one evaluation may run. The launcher evaluates on every keystroke and waits for the answer.
const TIME_LIMIT: Duration = Duration::from_millis(200);

pub struct FendContext {
    inner: Context,
    /// The exchange rates the app handed over, kept so a reset does not lose them.
    rates: Option<Arc<HashMap<String, f64>>>,
}

/// Exchange rates by currency code: how much of the currency one unit of the base currency buys.
/// They are answered from memory, so a preview at every keystroke may ask.
struct Rates(Arc<HashMap<String, f64>>);

impl ExchangeRateFnV2 for Rates {
    fn relative_to_base_currency(
        &self,
        currency: &str,
        _options: &ExchangeRateFnV2Options,
    ) -> Result<f64, Box<dyn std::error::Error + Send + Sync + 'static>> {
        self.0
            .get(currency)
            .copied()
            .ok_or_else(|| format!("there is no exchange rate for {currency}").into())
    }
}

impl FendContext {
    fn with_rates(rates: Option<Arc<HashMap<String, f64>>>) -> Self {
        let mut inner = Context::new();
        if let Some(rates) = &rates {
            inner.set_exchange_rate_handler_v2(Rates(Arc::clone(rates)));
        }
        Self { inner, rates }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FendSpanKind {
    Number = 0,
    BuiltInFunction = 1,
    Keyword = 2,
    String = 3,
    Date = 4,
    Whitespace = 5,
    Ident = 6,
    Boolean = 7,
    Other = 8,
}

impl From<fend_core::SpanKind> for FendSpanKind {
    fn from(kind: fend_core::SpanKind) -> Self {
        match kind {
            fend_core::SpanKind::Number => Self::Number,
            fend_core::SpanKind::BuiltInFunction => Self::BuiltInFunction,
            fend_core::SpanKind::Keyword => Self::Keyword,
            fend_core::SpanKind::String => Self::String,
            fend_core::SpanKind::Date => Self::Date,
            fend_core::SpanKind::Whitespace => Self::Whitespace,
            fend_core::SpanKind::Ident => Self::Ident,
            fend_core::SpanKind::Boolean => Self::Boolean,
            _ => Self::Other,
        }
    }
}

pub struct FendSpanInternal {
    string: CString,
    kind: FendSpanKind,
}

pub struct FendResult {
    is_ok: bool,
    value: Option<CString>,
    error: Option<CString>,
    is_empty: bool,
    spans: Vec<FendSpanInternal>,
}

pub struct FendCompletions {
    start: usize,
    items: Vec<CString>,
}

/// Stops an evaluation that is still running when its time is up.
struct Deadline(Instant);

impl Deadline {
    fn from_now() -> Self {
        Self(Instant::now() + TIME_LIMIT)
    }
}

impl Interrupt for Deadline {
    fn should_interrupt(&self) -> bool {
        Instant::now() >= self.0
    }
}

#[no_mangle]
pub extern "C" fn fend_context_new() -> *mut FendContext {
    let result = catch_unwind(|| {
        Box::into_raw(Box::new(FendContext::with_rates(None)))
    });
    result.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn fend_context_free(ctx: *mut FendContext) {
    if !ctx.is_null() {
        let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
            drop(Box::from_raw(ctx));
        }));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fend_context_reset(ctx: *mut FendContext) {
    if let Some(ctx) = ctx.as_mut() {
        let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
            *ctx = FendContext::with_rates(ctx.rates.take());
        }));
    }
}

/// Gives the context its exchange rates: `count` currency codes and, beside each, how much of it one unit of
/// the base currency buys. The base currency is in the list with a rate of 1. A count of 0 takes them away.
/// Variables are kept. A code that is not text, or a rate that is not a positive number, is left out.
#[no_mangle]
pub unsafe extern "C" fn fend_context_set_exchange_rates(
    ctx: *mut FendContext,
    codes: *const *const c_char,
    rates: *const f64,
    count: usize,
) {
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let Some(ctx) = ctx.as_mut() else { return };
        let mut table = HashMap::new();
        if !codes.is_null() && !rates.is_null() {
            for index in 0..count {
                let code = *codes.add(index);
                let rate = *rates.add(index);
                if code.is_null() || !rate.is_finite() || rate <= 0.0 {
                    continue;
                }
                if let Ok(code) = CStr::from_ptr(code).to_str() {
                    table.insert(code.to_owned(), rate);
                }
            }
        }
        let mut variables = Vec::new();
        let kept = ctx.inner.serialize_variables(&mut variables).is_ok();
        *ctx = FendContext::with_rates(if table.is_empty() { None } else { Some(Arc::new(table)) });
        if kept {
            let _ = ctx.inner.deserialize_variables(&mut variables.as_slice());
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn fend_context_serialize_variables(
    ctx: *mut FendContext,
    buffer: *mut u8,
    buffer_len: usize,
) -> i64 {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let ctx = match ctx.as_ref() {
            Some(c) => c,
            None => return -1,
        };
        let mut bytes = Vec::new();
        if ctx.inner.serialize_variables(&mut bytes).is_err() {
            return -1;
        }
        if buffer.is_null() {
            return bytes.len() as i64;
        }
        if buffer_len < bytes.len() {
            return -1;
        }
        ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        bytes.len() as i64
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn fend_context_deserialize_variables(
    ctx: *mut FendContext,
    bytes: *const u8,
    len: usize,
) -> i32 {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let ctx = match ctx.as_mut() {
            Some(c) => c,
            None => return -1,
        };
        if bytes.is_null() {
            return -1;
        }
        let slice = slice::from_raw_parts(bytes, len);
        let mut read = slice;
        if ctx.inner.deserialize_variables(&mut read).is_err() {
            return -1;
        }
        0
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn fend_evaluate(
    ctx: *mut FendContext,
    query: *const c_char,
) -> *mut FendResult {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let ctx = match ctx.as_mut() {
            Some(c) => c,
            None => return ptr::null_mut(),
        };
        if query.is_null() {
            return ptr::null_mut();
        }
        let query_str = match CStr::from_ptr(query).to_str() {
            Ok(s) => s,
            Err(e) => {
                let err_msg = CString::new(e.to_string()).unwrap_or_default();
                return Box::into_raw(Box::new(FendResult {
                    is_ok: false,
                    value: None,
                    error: Some(err_msg),
                    is_empty: false,
                    spans: Vec::new(),
                }));
            }
        };

        match fend_core::evaluate_with_interrupt(query_str, &mut ctx.inner, &Deadline::from_now()) {
            Ok(res) => {
                let main_res = res.get_main_result();
                let is_empty = res.output_is_empty();
                let val_cstring = CString::new(main_res).unwrap_or_default();
                let spans = res
                    .get_main_result_spans()
                    .filter(|s| !s.string().is_empty())
                    .map(|s| FendSpanInternal {
                        string: CString::new(s.string()).unwrap_or_default(),
                        kind: FendSpanKind::from(s.kind()),
                    })
                    .collect();
                Box::into_raw(Box::new(FendResult {
                    is_ok: true,
                    value: Some(val_cstring),
                    error: None,
                    is_empty,
                    spans,
                }))
            }
            Err(err) => {
                let err_cstring = CString::new(err).unwrap_or_default();
                Box::into_raw(Box::new(FendResult {
                    is_ok: false,
                    value: None,
                    error: Some(err_cstring),
                    is_empty: false,
                    spans: Vec::new(),
                }))
            }
        }
    }));
    result.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn fend_evaluate_preview(
    ctx: *mut FendContext,
    query: *const c_char,
) -> *mut FendResult {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let ctx = match ctx.as_mut() {
            Some(c) => c,
            None => return ptr::null_mut(),
        };
        if query.is_null() {
            return ptr::null_mut();
        }
        let query_str = match CStr::from_ptr(query).to_str() {
            Ok(s) => s,
            Err(e) => {
                let err_msg = CString::new(e.to_string()).unwrap_or_default();
                return Box::into_raw(Box::new(FendResult {
                    is_ok: false,
                    value: None,
                    error: Some(err_msg),
                    is_empty: false,
                    spans: Vec::new(),
                }));
            }
        };

        let res = fend_core::evaluate_preview_with_interrupt(query_str, &ctx.inner, &Deadline::from_now());
        let main_res = res.get_main_result();
        let is_empty = res.output_is_empty();
        let val_cstring = CString::new(main_res).unwrap_or_default();
        let spans = res
            .get_main_result_spans()
            .filter(|s| !s.string().is_empty())
            .map(|s| FendSpanInternal {
                string: CString::new(s.string()).unwrap_or_default(),
                kind: FendSpanKind::from(s.kind()),
            })
            .collect();
        Box::into_raw(Box::new(FendResult {
            is_ok: true,
            value: Some(val_cstring),
            error: None,
            is_empty,
            spans,
        }))
    }));
    result.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_free(res: *mut FendResult) {
    if !res.is_null() {
        let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
            drop(Box::from_raw(res));
        }));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_is_ok(res: *const FendResult) -> bool {
    res.as_ref().map(|r| r.is_ok).unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_is_empty(res: *const FendResult) -> bool {
    res.as_ref().map(|r| r.is_empty).unwrap_or(true)
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_get_value(res: *const FendResult) -> *const c_char {
    res.as_ref()
        .and_then(|r| r.value.as_ref())
        .map(|s| s.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_get_error(res: *const FendResult) -> *const c_char {
    res.as_ref()
        .and_then(|r| r.error.as_ref())
        .map(|s| s.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_get_span_count(res: *const FendResult) -> usize {
    res.as_ref().map(|r| r.spans.len()).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_get_span_string(
    res: *const FendResult,
    index: usize,
) -> *const c_char {
    res.as_ref()
        .and_then(|r| r.spans.get(index))
        .map(|s| s.string.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn fend_result_get_span_kind(
    res: *const FendResult,
    index: usize,
) -> FendSpanKind {
    res.as_ref()
        .and_then(|r| r.spans.get(index))
        .map(|s| s.kind)
        .unwrap_or(FendSpanKind::Other)
}

#[no_mangle]
pub unsafe extern "C" fn fend_get_completions(prefix: *const c_char) -> *mut FendCompletions {
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        if prefix.is_null() {
            return ptr::null_mut();
        }
        let prefix_str = match CStr::from_ptr(prefix).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };

        let (start, completions) = fend_core::get_completions_for_prefix(prefix_str);
        let items: Vec<CString> = completions
            .into_iter()
            .filter_map(|c| CString::new(c.display()).ok())
            .collect();

        Box::into_raw(Box::new(FendCompletions { start, items }))
    }));
    result.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn fend_completions_free(completions: *mut FendCompletions) {
    if !completions.is_null() {
        let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
            drop(Box::from_raw(completions));
        }));
    }
}

#[no_mangle]
pub unsafe extern "C" fn fend_completions_get_count(completions: *const FendCompletions) -> usize {
    completions.as_ref().map(|c| c.items.len()).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn fend_completions_get_start_index(completions: *const FendCompletions) -> usize {
    completions.as_ref().map(|c| c.start).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn fend_completions_get_item(
    completions: *const FendCompletions,
    index: usize,
) -> *const c_char {
    completions
        .as_ref()
        .and_then(|c| c.items.get(index))
        .map(|s| s.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn fend_get_version() -> *const c_char {
    static VERSION: std::sync::OnceLock<CString> = std::sync::OnceLock::new();
    let c_str = VERSION.get_or_init(|| {
        CString::new(fend_core::get_version()).unwrap_or_default()
    });
    c_str.as_ptr()
}

#[cfg(test)]
mod tests;
