#!/usr/bin/env bash
#
# hugo/mayhem/build.sh — build the `fuzzmarkdownify` libFuzzer target (the old
# fork's Mayhem target name, preserved for corpus/defect continuity): Go's
# native libFuzzer instrumentation (-gcflags=all=-d=libfuzzer, buildmode
# c-archive) over mayhem/fuzzmarkdownify (cgo LLVMFuzzerTestOneInput export ->
# mayhem/fuzzing.Fuzz -> transform.Markdownify), linked with clang
# -fsanitize=fuzzer(,address).
#
# Also warms the Go build cache for the FULL upstream test suite (compiles every
# test package, runs nothing) so mayhem/test.sh only runs pre-compiled tests.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only (Go code is not ASan-instrumented; ASan covers the
# C shims + runtime interop). An explicit empty --build-arg SANITIZER_FLAGS=
# disables the sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS MAYHEM_JOBS

# Debug-info flags (SPEC §6.2 item 10): Go's gc compiler has no DWARF-version
# knob (emits DWARF4/5), so a tiny C anchor CU compiled with -gdwarf-3 is linked
# FIRST — the first CU in .debug_info is DWARF3 and the DWARF<4 triage gate
# passes. CGO shim compiles get the same flags.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"
export CGO_ENABLED=1

# Go env: toolchain pinned under /opt/toolchains (SPEC §6.2 item 8) —
# $HOME-independent, so the module/build caches survive the PATCH re-run under a
# different identity.
export GOFLAGS="${GOFLAGS:--mod=mod -buildvcs=false}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export GOPATH="${GOPATH:-/opt/toolchains/go-path}"
export GOCACHE="${GOCACHE:-/opt/toolchains/go-path/build-cache}"
export GOMODCACHE="${GOMODCACHE:-/opt/toolchains/go-path/pkg/mod}"
export PATH="/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:$PATH"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE. The
# module cache doubles as a file proxy at $GOMODCACHE/cache/download — file
# proxy FIRST, network LAST, so the offline re-run resolves entirely from the
# cache and the network only fills cache-misses on the first (online) build.
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"

cd "$SRC"
go version

mkdir -p "$SRC/mayhem-build"

TARGET="fuzzmarkdownify"
echo "=== building $TARGET (go native libFuzzer c-archive) ==="
go build -tags libfuzzer -buildmode=c-archive "-gcflags=all=-d=libfuzzer" \
  -o "$SRC/mayhem-build/$TARGET.a" ./mayhem/fuzzmarkdownify

# DWARF3 anchor CU, linked first so the first .debug_info CU is DWARF < 4.
printf 'int mayhem_dwarf3_anchor;\n' > "$SRC/mayhem-build/dwarf3-anchor.c"
$CC -c $GO_DEBUG_FLAGS -o "$SRC/mayhem-build/dwarf3-anchor.o" "$SRC/mayhem-build/dwarf3-anchor.c"

$CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS \
  "$SRC/mayhem-build/dwarf3-anchor.o" "$SRC/mayhem-build/$TARGET.a" \
  -o "/mayhem/$TARGET" -lpthread
echo "built /mayhem/$TARGET"

# ── Pre-compile the FULL upstream test suite (NORMAL flags — functional oracle).
# `-run '^$'` compiles every test package and executes each binary with an
# empty test filter (milliseconds), fully warming GOCACHE so mayhem/test.sh's
# `go test ./...` only RUNS the already-compiled suite.
echo "=== pre-compiling upstream test suite (go test -run '^$' ./...) ==="
go test -count=1 -run '^$' ./...

echo "build.sh complete:"
ls -la "/mayhem/$TARGET"
