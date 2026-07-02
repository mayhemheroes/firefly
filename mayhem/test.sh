#!/usr/bin/env bash
#
# mayhem/test.sh — RUN firefly_session's OWN test suite (already compiled by
# mayhem/build.sh via `cargo test --no-run` into $SRC/mayhem/test-target).
#
# Anti-reward-hack: we assert on the suite's OUTPUT MARKERS ("test result: ok. N
# passed; M failed"), not just exit status — a PATCH that neuters the program to
# exit(0) produces no such marker (or 0 passed) and FAILS here. Emits a CTRF summary.
#
# KNOWN-BROKEN UPSTREAM ASSERTIONS (excluded by name, NOT patched — cardinal rule: we
# never touch upstream source): compiler/session/src/config/app.rs's 3
# config::app::test::invalid_manifest_* tests are #[should_panic(expected = "...")]
# but the shared `parse()` test helper (app.rs:575) panics with the LITERAL string
# "parsing failed" instead of forwarding the real diagnostic text, so the substring
# match always fails even though App::parse_str DOES correctly reject the bad input
# and DOES panic. Pre-existing upstream test-harness bug, unrelated to our harness or
# to App::parse_str itself. We exclude just these 3 by exact substring ("invalid_manifest"
# matches ONLY these 3 in the whole session crate — verified via grep) and keep every
# other real test (incl. simple_app_resource_test / rich_app_resource_test, the
# App::parse_str-adjacent happy-path oracle) running for real.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TARGET_DIR="$SRC/mayhem/test-target"

# Locate the prebuilt unit-test runner(s) (cargo names them <crate>-<hash>).
mapfile -t RUNNERS < <(find "$TARGET_DIR/debug/deps" -maxdepth 1 -type f -name 'firefly_session-*' -executable 2>/dev/null)
if [ "${#RUNNERS[@]}" -eq 0 ]; then
  echo "FATAL: no prebuilt test runner under $TARGET_DIR/debug/deps — build.sh should have produced it" >&2
  emit_ctrf "cargo-test" 0 1
  exit 1
fi

passed_total=0
failed_total=0
saw_marker=0

for runner in "${RUNNERS[@]}"; do
  echo "=== running $runner ==="
  out="$("$runner" --test-threads="$MAYHEM_JOBS" --skip invalid_manifest 2>&1)" && rc=0 || rc=$?
  echo "$out"
  while IFS= read -r line; do
    if [[ "$line" =~ test\ result:.*\ ([0-9]+)\ passed\;\ ([0-9]+)\ failed ]]; then
      passed_total=$(( passed_total + ${BASH_REMATCH[1]} ))
      failed_total=$(( failed_total + ${BASH_REMATCH[2]} ))
      saw_marker=1
    fi
  done <<< "$out"
  if [ "$rc" -ne 0 ] && [ "$saw_marker" -eq 0 ]; then
    failed_total=$(( failed_total + 1 ))
  fi
done

# No summary marker at all => the binary never ran the real suite (neutered/no-op) => FAIL.
if [ "$saw_marker" -eq 0 ]; then
  echo "FATAL: no libtest 'test result:' marker seen — suite did not run" >&2
  emit_ctrf "cargo-test" 0 1
  exit 1
fi
# Sanity floor: the suite must actually pass tests.
if [ "$passed_total" -eq 0 ]; then
  echo "FATAL: 0 tests passed — oracle would be vacuous" >&2
  emit_ctrf "cargo-test" 0 $(( failed_total > 0 ? failed_total : 1 ))
  exit 1
fi

emit_ctrf "cargo-test" "$passed_total" "$failed_total"
