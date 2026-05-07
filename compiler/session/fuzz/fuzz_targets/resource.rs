#![no_main]
use libfuzzer_sys::fuzz_target;
use std::sync::Arc;
use firefly_diagnostics::CodeMap;
use firefly_util::diagnostics::{ColorChoice, DefaultEmitter, DiagnosticsConfig, DiagnosticsHandler};

fuzz_target!(|data: &str| {
    let emitter = Arc::new(DefaultEmitter::new(ColorChoice::Never));
    let codemap = Arc::new(CodeMap::new());
    let diagnostics =
        DiagnosticsHandler::new(DiagnosticsConfig::default(), codemap.clone(), emitter);
    let _ = firefly_session::App::parse_str(&diagnostics, codemap, data);
});
