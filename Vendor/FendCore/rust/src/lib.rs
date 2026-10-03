use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::catch_unwind;
use std::ptr;
use std::slice;
use fend_core::{Context, Interrupt};

pub struct FendContext {
    inner: Context,
}

pub struct FendResult {
    is_ok: bool,
    value: Option<CString>,
    error: Option<CString>,
    is_empty: bool,
}

pub struct FendCompletions {
    start: usize,
    items: Vec<CString>,
}

struct NoInterrupt;
impl Interrupt for NoInterrupt {
    fn should_interrupt(&self) -> bool {
        false
    }
}

#[no_mangle]
pub extern "C" fn fend_context_new() -> *mut FendContext {
    let result = catch_unwind(|| {
        Box::into_raw(Box::new(FendContext {
            inner: Context::new(),
        }))
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
            ctx.inner = Context::new();
        }));
    }
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
                }));
            }
        };

        match fend_core::evaluate(query_str, &mut ctx.inner) {
            Ok(res) => {
                let main_res = res.get_main_result();
                let is_empty = res.output_is_empty();
                let val_cstring = CString::new(main_res).unwrap_or_default();
                Box::into_raw(Box::new(FendResult {
                    is_ok: true,
                    value: Some(val_cstring),
                    error: None,
                    is_empty,
                }))
            }
            Err(err) => {
                let err_cstring = CString::new(err).unwrap_or_default();
                Box::into_raw(Box::new(FendResult {
                    is_ok: false,
                    value: None,
                    error: Some(err_cstring),
                    is_empty: false,
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
                }));
            }
        };

        let res = fend_core::evaluate_preview_with_interrupt(query_str, &mut ctx.inner, &NoInterrupt);
        let main_res = res.get_main_result();
        let is_empty = res.output_is_empty();
        let val_cstring = CString::new(main_res).unwrap_or_default();
        Box::into_raw(Box::new(FendResult {
            is_ok: true,
            value: Some(val_cstring),
            error: None,
            is_empty,
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
