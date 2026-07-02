# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — RUST target (cargo-fuzz / libfuzzer-sys). Builds ON TOP of the
# org C/C++ base (ghcr.io/mayhemheroes/base), adding a pinned Rust toolchain +
# cargo-fuzz under /opt/toolchains/rust, then runs mayhem/build.sh.

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS

# Firefly's OWN upstream CI (.github/workflows/x86_64-unknown-linux-gnu-compiler.yml,
# CARGO_MAKE_TOOLCHAIN) pins `nightly-2023-02-07` — the codebase uses now-removed
# nightly features (box_syntax in compiler/macros, const_default_impls in
# runtimes/emulator + library/system) that only exist on nightlies from that era,
# AND Cargo workspace-inheritance (version.workspace = true, etc. — stabilized in
# Cargo 1.64, Sept 2022), so anything OLDER than ~2022-09 fails to even parse the
# manifests. The fleet-standard nightly-2025-05-14 cannot compile this repo either
# way (removed features). Match upstream's own pin exactly.
ARG RUST_CHANNEL=nightly-2023-02-07
ARG CARGO_FUZZ_VERSION=0.11.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 && chown -R 2000:2000 /opt/toolchains/rust

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
