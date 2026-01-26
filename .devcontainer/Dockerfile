FROM mcr.microsoft.com/devcontainers/base:trixie

ARG TARGETARCH
ARG ZIG_VERSION=0.15.2

RUN ZIG_ARCH=$([ "$TARGETARCH" = "amd64" ] && echo x86_64 || echo aarch64) && \
    mkdir -p /usr/local/zig && \
    curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-$ZIG_ARCH-linux-$ZIG_VERSION.tar.xz" \
    | tar -xJ -C /usr/local/zig --strip-components=1 && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig
