#![deny(warnings)]
#![feature(box_patterns)]

mod bimap;
mod ir;
pub mod macros;
pub mod passes;
mod printer;

pub use self::bimap::{BiMap, Name};
pub use self::ir::*;
