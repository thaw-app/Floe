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

#[test]
fn test_a_shift_too_large_for_the_deadline_is_refused() {
    unsafe {
        let ctx = fend_context_new();
        assert_eq!(value(ctx, "1 << 8", false).unwrap(), "256");
        assert_eq!(value(ctx, "(1 << 4) + 1", false).unwrap(), "17");
        assert_eq!(value(ctx, "1 << 3 << 2", false).unwrap(), "32");

        // fend would make room for these bits a word at a time, for minutes, without looking at the deadline.
        for query in ["1 << 100000000", "1 << 65537", "1 << 10^9", "1 << (100000000)", "x = 100000000; 1 << x"] {
            let started = Instant::now();
            assert_eq!(value(ctx, query, false).unwrap_err(), "interrupted", "{query}");
            assert_eq!(value(ctx, query, true).unwrap(), "", "{query}: a refused preview is empty");
            assert!(started.elapsed() < Duration::from_secs(1), "{query}");
        }
        fend_context_free(ctx);
    }
}

#[test]
fn test_a_query_too_long_to_parse_in_time_is_refused() {
    unsafe {
        let ctx = fend_context_new();
        // fend's parser copies the product so far at every term: 2000 of them take half a second before the deadline is checked.
        let product = vec!["1"; 2000].join("*");
        let started = Instant::now();
        assert_eq!(value(ctx, &product, false).unwrap_err(), "interrupted");
        assert_eq!(value(ctx, &product, true).unwrap(), "");
        assert!(started.elapsed() < Duration::from_millis(100));

        let product = vec!["1"; 500].join("*");
        assert_eq!(value(ctx, &product, false).unwrap(), "1", "a product within the limit is answered");
        fend_context_free(ctx);
    }
}

#[test]
fn test_deep_brackets_do_not_overflow_a_small_stack() {
    // 80 brackets overflowed a 512 KB stack, the size of a background thread the app may call from, and aborted.
    let query = format!("{}1{}", "(".repeat(500), ")".repeat(500));
    let answer = std::thread::Builder::new()
        .stack_size(512 * 1024)
        .spawn(move || unsafe {
            let ctx = fend_context_new();
            let answer = value(ctx, &query, false);
            fend_context_free(ctx);
            answer
        })
        .unwrap()
        .join()
        .unwrap();
    assert_eq!(answer.unwrap(), "1");
}

#[test]
fn test_saved_variables_that_claim_more_than_they_hold_are_refused() {
    unsafe {
        let ctx = fend_context_new();
        assert_eq!(value(ctx, "x = 4", false).unwrap(), "4");
        let mut saved = vec![0u8; fend_context_serialize_variables(ctx, ptr::null_mut(), 0) as usize];
        fend_context_serialize_variables(ctx, saved.as_mut_ptr(), saved.len());

        let other = fend_context_new();
        assert_eq!(fend_context_deserialize_variables(other, saved.as_ptr(), saved.len()), 0);
        assert_eq!(value(other, "x + 1", false).unwrap(), "5", "a context's own variables are read back");

        let refused: [&[u8]; 6] = [
            // Nine bytes that ask fend to make room for 2^60 variables.
            &[0x1b, 0x10, 0, 0, 0, 0, 0, 0, 0],
            // One variable claimed, nothing after it.
            &[0x01],
            // A name 4 GB long.
            &[0x01, 0x7a, 0xff, 0xff, 0xff, 0xff, b'x'],
            // An array of 2^32 items.
            &[0x01, 0x61, b'x', 0x9a, 0xff, 0xff, 0xff, 0xff],
            // The count cut short.
            &[0x19, 0x01],
            // Not an integer first.
            &[0x61, b'x'],
        ];
        for bytes in refused {
            assert_eq!(fend_context_deserialize_variables(other, bytes.as_ptr(), bytes.len()), -1, "{bytes:?}");
        }
        let mut nested = vec![0x01, 0x61, b'x'];
        nested.extend(std::iter::repeat_n(0x81, 1000));
        nested.push(0x00);
        assert_eq!(fend_context_deserialize_variables(other, nested.as_ptr(), nested.len()), -1, "arrays 1000 deep");
        assert_eq!(value(other, "x + 1", false).unwrap(), "5", "a refused file leaves the variables as they were");
        assert_eq!(fend_context_deserialize_variables(other, [0u8].as_ptr(), 1), 0, "no variables at all");

        fend_context_free(other);
        fend_context_free(ctx);
    }
}

#[test]
fn test_saved_variables_of_every_kind_are_read_back_as_they_were() {
    unsafe {
        let ctx = fend_context_new();
        let definitions = [
            ("mass", "5 kg"),
            ("speed", "3 m/s"),
            ("third", "1/3"),
            ("word", "\"hello\""),
            ("yes", "true"),
            ("price", "3.25"),
            ("big", "2^100"),
            ("square", "x: x^2"),
        ];
        let mut expected = Vec::new();
        for (name, definition) in definitions {
            let assigned = value(ctx, &format!("{name} = {definition}"), false).unwrap();
            expected.push((name, assigned));
        }
        let mut saved = vec![0u8; fend_context_serialize_variables(ctx, ptr::null_mut(), 0) as usize];
        fend_context_serialize_variables(ctx, saved.as_mut_ptr(), saved.len());

        let fresh = fend_context_new();
        assert_eq!(fend_context_deserialize_variables(fresh, saved.as_ptr(), saved.len()), 0, "fend's own saved variables are accepted");
        for (name, assigned) in &expected {
            assert_eq!(&value(fresh, name, false).unwrap(), assigned, "{name}");
        }
        assert_eq!(value(fresh, "mass to g", false).unwrap(), "5000 g");
        assert_eq!(value(fresh, "square 4", false).unwrap(), "16");

        fend_context_free(fresh);
        fend_context_free(ctx);
    }
}
