FROM mcr.microsoft.com/devcontainers/base:trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      clang lld lldb \
 && rm -rf /var/lib/apt/lists/*
