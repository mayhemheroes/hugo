#!/usr/bin/env bash
#
# hugo/mayhem/test.sh — RUN hugo's ENTIRE upstream Go test suite (go test ./...,
# every package: hugolib, markup, tpl, resources, parser, commands, …) and emit
# a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: hugo's suite is a real known-answer suite — thousands of
# cases assert rendered output, parsed values and golden files via qt matchers,
# so a no-op/exit(0) patch FAILS it. Tests that need missing external tools
# (asciidoctor, pandoc, dart-sass, …) self-skip upstream and are counted as
# skipped.
#
# This script does NOT compile from cold: mayhem/build.sh pre-compiled every
# test package into the pinned GOCACHE (go test -run '^$' ./...), so `go test`
# here only runs the already-built binaries. The §6.3 sabotage check LD_PRELOADs
# an exit(0) constructor into every non-system executable — that neuters the
# `go` tool itself (under /opt/toolchains) and every test binary, so zero test
# events are parsed and this oracle FAILS (not reward-hackable).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
# codegen's tests require the working dir path to contain "hugo" (upstream
# checks ProjectRootDir for the Hugo root); $SRC is /mayhem, so run the suite
# through a hugo-named symlink.
HUGO_DIR=/tmp/hugo
[ -e "$HUGO_DIR" ] || ln -s "$SRC" "$HUGO_DIR"
cd "$HUGO_DIR"

export GOFLAGS="${GOFLAGS:--mod=mod -buildvcs=false}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export GOPATH="${GOPATH:-/opt/toolchains/go-path}"
export GOCACHE="${GOCACHE:-/opt/toolchains/go-path/build-cache}"
export GOMODCACHE="${GOMODCACHE:-/opt/toolchains/go-path/pkg/mod}"
export PATH="/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:$PATH"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export CGO_ENABLED=1

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

OUT="/tmp/hugo-test.out"
echo "=== running hugo's full upstream suite: go test -count=1 ./... ==="
go test -v -count=1 -timeout 60m ./... > "$OUT" 2>&1; rc=$?
tail -20 "$OUT"
# Surface package build/vet errors (they precede the FAIL summary lines).
grep -E '\[build failed\]|^# |cannot |undefined:|no space left' "$OUT" | head -40 || true

# Count TOP-LEVEL test results only ('^--- ' — subtests are indented '    --- ').
PASSED=$(grep -c '^--- PASS: ' "$OUT" || true)
FAILED=$(grep -c '^--- FAIL: ' "$OUT" || true)
SKIPPED=$(grep -c '^--- SKIP: ' "$OUT" || true)
: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"

# A neutered/silent run (or a crash before any test ran) parses as 0 events — fail honestly.
if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
  echo "no test results parsed from go test output (exit $rc) — treating as failure" >&2
  emit_ctrf "go-test" 0 1 0; exit 1
fi
# Trust parsed failures; if go test exited non-zero with 0 parsed failures
# (package build failure, panic outside a test), force one.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi

# ── Behavioral probe (§6.3): run the fuzz target single-shot on a markdown seed
# and assert libFuzzer's "Executed" marker — proves the binary actually drives
# transform.Markdownify (and fails under the sabotage LD_PRELOAD).
if [ -x /mayhem/fuzzmarkdownify ]; then
  echo "=== behavioral probe: fuzzmarkdownify single-shot ==="
  printf '# Title\n\nSome *text*.\n' > /tmp/markdownify-probe.md
  PROBE_OUT=$(/mayhem/fuzzmarkdownify -runs=1 /tmp/markdownify-probe.md 2>&1 || true)
  if echo "$PROBE_OUT" | grep -q "Executed"; then
    echo "PROBE PASS: fuzzmarkdownify executed the seed"
    PASSED=$(( PASSED + 1 ))
  else
    echo "PROBE FAIL: fuzzmarkdownify produced no 'Executed' output"; echo "$PROBE_OUT" | tail -5
    FAILED=$(( FAILED + 1 ))
  fi
fi

emit_ctrf "go-test" "$PASSED" "$FAILED" "$SKIPPED"
