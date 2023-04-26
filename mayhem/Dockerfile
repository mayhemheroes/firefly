# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd compiler/session/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv compiler/session/fuzz/target/x86_64-unknown-linux-gnu/release/resource /resource && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd compiler/session/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv compiler/session/fuzz/target/release/resource /resource_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /resource /resource_no_inst /
