# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — hugo (pure Go). Builds ON TOP of the org C/C++ base
# (clang links the Go libFuzzer c-archive), adding a pinned Go toolchain under
# /opt/toolchains/go, then runs mayhem/build.sh (native -d=libfuzzer build of
# the fuzzmarkdownify target + test-suite cache warm) and mayhem/test.sh
# (hugo's full upstream `go test ./...` suite).
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t hugo-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV —
# an empty value breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# Pin the Go toolchain version AND its tarball sha256 (reproducible fetch).
# hugo's go.mod requires go >= 1.26.0.
ARG GO_VERSION=1.26.5
ARG GO_SHA256=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053

# ── Go toolchain @ a FIXED, lockable, $HOME-independent prefix ────────────────
# SPEC §6.2 item 8 + §6.5: the commit build and the PATCH re-run run under
# DIFFERENT $HOMEs. Pinning GOROOT/GOPATH/GOMODCACHE/GOCACHE under
# /opt/toolchains ensures the caches populated during this first (online) build
# are found again when build.sh/test.sh re-run offline.
ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/build-cache \
    GOTOOLCHAIN=local \
    GOFLAGS="-mod=mod -buildvcs=false" \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin

USER root
RUN install -d /opt/toolchains/go-path \
 && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
 && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
 && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm -f /tmp/go.tgz \
 && go version \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it
 # must read the toolchain and read/refresh the caches, so hand the GOPATH to 2000.
 && chown -R 2000:2000 /opt/toolchains/go-path

# Source enters from the build CONTEXT (the CI checkout): the FULL repo
# (incl. .git history) is copied to /mayhem; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates the caches (online, this first build) and builds the libFuzzer target.
RUN bash mayhem/build.sh

# Run hugo's own full test suite at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
