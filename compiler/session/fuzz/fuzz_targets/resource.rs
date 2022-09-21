#![no_main]
use libfuzzer_sys::fuzz_target;
use std::sync::Arc;
use firefly_diagnostics::{
    CodeMap, Reporter,
};

fuzz_target!(|data: &str| {
    let reporter = Reporter::new();
    let codemap = Arc::new(CodeMap::new());
    _ = firefly_session::App::parse_str(&reporter, codemap.clone(), data);
});
