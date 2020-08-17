use crate::erts::exception::RuntimeException;
use crate::erts::fragment::HeapFragment;
use crate::erts::term::prelude::*;

use liblumen_core::util::thread_local::ThreadLocalCell;

use super::Process;

/// This type is used to communicate error information between
/// the native code of a process, and the scheduler/caller.
///
/// Error info (when applicable) is communicated separately.
#[allow(unused)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum ProcessSignal {
    /// No signal set
    None = 0,
    /// The process should yield/has yielded
    Yield,
    /// Operation failed due to allocation failure,
    /// or process requires garbage collection
    GarbageCollect,
    /// The process raised an error
    Error,
    /// The process exited
    Exit,
}

extern "C" {
    #[link_name = "__lumen_process_signal"]
    #[thread_local]
    static mut PROCESS_SIGNAL: ProcessSignal;

    #[link_name = "__lumen_start_panic"]
    fn lumen_panic(err: Term) -> !;
}

// Holds the current RuntimeException generated by the runtime, if present
thread_local!(static PROCESS_ERROR: ThreadLocalCell<Option<RuntimeException>> = ThreadLocalCell::new(None));

/// Returns the current value of the process signal
#[inline(always)]
pub fn process_signal() -> ProcessSignal {
    unsafe { PROCESS_SIGNAL }
}

/// Sets the process signal value
#[inline(always)]
pub fn set_process_signal(value: ProcessSignal) {
    unsafe {
        PROCESS_SIGNAL = value;
    }
}

/// Clears the process signal value
#[inline(always)]
pub fn clear_process_signal() {
    unsafe {
        PROCESS_SIGNAL = ProcessSignal::None;
    }
}

pub fn process_raise(process: &Process, err: RuntimeException) -> ! {
    let error_tuple = {
        let mut heap = process.acquire_heap();
        err.as_error_tuple(&mut heap)
    };

    let exception = if std::intrinsics::unlikely(error_tuple.is_err()) {
        let layout = Tuple::layout_for_len(3);
        let mut heap_fragment = HeapFragment::new(layout).expect("out of memory");
        let heap_fragment_ref = unsafe { heap_fragment.as_mut() };

        let tuple = err
            .as_error_tuple(heap_fragment_ref)
            .expect("bug: should only need 3 words for exception tuple");

        process.attach_fragment(heap_fragment_ref);

        tuple
    } else {
        error_tuple.unwrap()
    };

    unsafe {
        PROCESS_ERROR.with(|cell| cell.replace(Some(err)));

        lumen_panic(exception);
    }
}

/// Gets the process error value
#[inline]
pub fn process_error() -> Option<RuntimeException> {
    unsafe { PROCESS_ERROR.with(|cell| cell.replace(None)) }
}
