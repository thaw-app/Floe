use super::*;

#[test]
fn test_evaluate_spans() {
    unsafe {
        let ctx = fend_context_new();
        assert!(!ctx.is_null());

        let query = CString::new("1 + 1").unwrap();
        let res = fend_evaluate(ctx, query.as_ptr());
        assert!(!res.is_null());
        assert!(fend_result_is_ok(res));
        assert!(!fend_result_is_empty(res));

        let val = CStr::from_ptr(fend_result_get_value(res)).to_str().unwrap();
        assert_eq!(val, "2");

        let count = fend_result_get_span_count(res);
        assert_eq!(count, 1);
        let s0 = CStr::from_ptr(fend_result_get_span_string(res, 0)).to_str().unwrap();
        assert_eq!(s0, "2");
        assert_eq!(fend_result_get_span_kind(res, 0), FendSpanKind::Number);

        fend_result_free(res);
        fend_context_free(ctx);
    }
}

unsafe fn value(ctx: *mut FendContext, query: &str, preview: bool) -> Result<String, String> {
    let query = CString::new(query).unwrap();
    let res = if preview { fend_evaluate_preview(ctx, query.as_ptr()) } else { fend_evaluate(ctx, query.as_ptr()) };
    let answer = if fend_result_is_ok(res) {
        Ok(CStr::from_ptr(fend_result_get_value(res)).to_str().unwrap().to_owned())
    } else {
        Err(CStr::from_ptr(fend_result_get_error(res)).to_str().unwrap().to_owned())
    };
    fend_result_free(res);
    answer
}

#[test]
fn test_exchange_rates_convert_money_and_outlast_a_reset() {
    unsafe {
        let ctx = fend_context_new();
        assert!(value(ctx, "10 EUR to USD", false).unwrap_err().contains("exchange rates"));

        let codes = [CString::new("EUR").unwrap(), CString::new("USD").unwrap(), CString::new("JPY").unwrap(), CString::new("BAD").unwrap()];
        let pointers: Vec<*const c_char> = codes.iter().map(|code| code.as_ptr()).collect();
        let rates = [1.0, 1.25, 160.0, -3.0];
        fend_context_set_exchange_rates(ctx, pointers.as_ptr(), rates.as_ptr(), rates.len());

        assert_eq!(value(ctx, "10 EUR to USD", false).unwrap(), "12.5 USD");
        assert_eq!(value(ctx, "10 EUR to USD", true).unwrap(), "12.5 USD", "a preview is answered from memory too");
        assert_eq!(value(ctx, "320 JPY to USD", false).unwrap(), "2.5 USD", "through the base currency");
        assert!(value(ctx, "1 EUR to GBP", false).unwrap_err().contains("GBP"), "a currency with no rate says which");

        fend_context_reset(ctx);
        assert_eq!(value(ctx, "10 EUR to USD", false).unwrap(), "12.5 USD");

        assert_eq!(value(ctx, "x = 4", false).unwrap(), "4");
        fend_context_set_exchange_rates(ctx, ptr::null(), ptr::null(), 0);
        assert!(value(ctx, "10 EUR to USD", false).is_err(), "taken away again");
        assert_eq!(value(ctx, "x + 1", false).unwrap(), "5", "variables are kept across a change of rates");

        fend_context_free(ctx);
    }
}

#[test]
fn test_preview_spans() {
    unsafe {
        let ctx = fend_context_new();
        assert!(!ctx.is_null());

        let query = CString::new("5 ft in meters").unwrap();
        let res = fend_evaluate_preview(ctx, query.as_ptr());
        assert!(!res.is_null());
        assert!(fend_result_is_ok(res));
        assert!(!fend_result_is_empty(res));

        let count = fend_result_get_span_count(res);
        assert_eq!(count, 2);

        let s0 = CStr::from_ptr(fend_result_get_span_string(res, 0)).to_str().unwrap();
        assert_eq!(s0, "1.524");
        assert_eq!(fend_result_get_span_kind(res, 0), FendSpanKind::Number);

        let s1 = CStr::from_ptr(fend_result_get_span_string(res, 1)).to_str().unwrap();
        assert_eq!(s1, " meters");
        assert_eq!(fend_result_get_span_kind(res, 1), FendSpanKind::Ident);

        fend_result_free(res);
        fend_context_free(ctx);
    }
}

#[test]
fn test_long_evaluation_stops_at_the_time_limit() {
    unsafe {
        let ctx = fend_context_new();
        assert!(!ctx.is_null());

        // A factorial this size runs for minutes when nothing interrupts it.
        let query = CString::new("10000000!").unwrap();
        let started = Instant::now();
        let res = fend_evaluate(ctx, query.as_ptr());
        assert!(started.elapsed() < Duration::from_secs(2));
        assert!(!res.is_null());
        assert!(!fend_result_is_ok(res));

        // A preview never fails: one that ran out of time comes back empty.
        let started = Instant::now();
        let preview = fend_evaluate_preview(ctx, query.as_ptr());
        assert!(started.elapsed() < Duration::from_secs(2));
        assert!(!preview.is_null());
        assert!(fend_result_is_empty(preview));

        fend_result_free(res);
        fend_result_free(preview);
        fend_context_free(ctx);
    }
}
