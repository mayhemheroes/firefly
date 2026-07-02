#!/usr/bin/env bash
#
# mayhem/build.sh — build firefly's cargo-fuzz target(s) as sanitized libFuzzer
# binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), then build the
# upstream test suite so mayhem/test.sh can RUN it.
#
# Runs inside the commit image as `mayhem` in /mayhem.
# Toolchain + cargo registry at $CARGO_HOME=/opt/toolchains/rust/cargo (absolute,
# $HOME-independent). AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS
# script OFFLINE — this first (online) build populates the registry; do NOT
# hard-code --offline (rlenv runtime sets CARGO_NET_OFFLINE=true for the re-run).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Sanitizers (§6.1): honor the KNOB; when $SANITIZER_FLAGS is non-empty add ASan.
RUST_SAN=""
if [ -n "${SANITIZER_FLAGS:-}" ]; then
  RUST_SAN="-Zsanitizer=address"
fi

# Debug info (§6.2 item 10): DWARF < 4 required. rustc nightly defaults to DWARF-5.
export RUSTFLAGS="${RUSTFLAGS:-} ${RUST_DEBUG_FLAGS:-} --cfg fuzzing ${RUST_SAN} -Zdwarf-version=3 -Cdebuginfo=1 -Cforce-frame-pointers"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# Strip DWARF-5 from the bundled ASan runtime archive (toolchain artifact, NOT project code).
# Idempotent: --strip-debug on an already-stripped archive is a no-op.
if [ -n "${RUST_SAN}" ]; then
  RT_LIB_DIR="$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/lib"
  for asan in "$RT_LIB_DIR"/librustc-*_rt.asan.a; do
    [ -f "$asan" ] || continue
    if [ -w "$asan" ]; then
      objcopy --strip-debug "$asan" "$asan.stripped" && mv "$asan.stripped" "$asan"
      echo "stripped debug info from bundled ASan runtime: $asan"
    fi
  done
fi

# The existing cargo-fuzz crate at compiler/session/fuzz/ harnesses App::parse_str.
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the upstream test suite (normal flags, debug build) so mayhem/test.sh can RUN it.
# Debug build (no --release) keeps debug_assertions/assert! live — oracle must bite a neutered binary.
echo "=== cargo test --no-run (firefly_session, normal flags) ==="
env -u RUSTFLAGS -u CFLAGS -u CXXFLAGS \
  cargo test --no-run -p firefly_session --target-dir "$SRC/mayhem/test-target" 2>&1 | tail -30

echo "build.sh complete"
