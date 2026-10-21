# kvbox guest kernel: Linux 6.1 LTS, Firecracker's CI config plus kvbox.config (Docker needs
# netfilter tables the CI config leaves out). Built by kernel/build.sh; the output stage holds
# only the uncompressed vmlinux Firecracker boots and the .config it was built with.
FROM ubuntu:24.04 AS build
ARG KERNEL_VERSION
ARG KERNEL_SHA256
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential bc bison flex libelf-dev libssl-dev cpio xz-utils \
      curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSL --retry 3 -o linux.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" \
    && echo "${KERNEL_SHA256}  linux.tar.xz" | sha256sum -c - \
    && tar -xf linux.tar.xz --strip-components=1 && rm linux.tar.xz

COPY firecracker-ci-x86_64-6.1.config kvbox.config /cfg/
RUN scripts/kconfig/merge_config.sh -m -O . /cfg/firecracker-ci-x86_64-6.1.config /cfg/kvbox.config >/dev/null \
    && make olddefconfig >/dev/null \
    # Every option kvbox.config asks for must have survived olddefconfig.
    && missing=0; for want in $(grep -E '^CONFIG_' /cfg/kvbox.config); do \
         grep -qxF "$want" .config || { echo "kernel config: $want did not take" >&2; missing=1; }; \
       done; [ "$missing" = 0 ]
RUN make -j"$(nproc)" vmlinux >/dev/null && ls -la vmlinux

FROM scratch AS out
COPY --from=build /src/vmlinux /vmlinux
COPY --from=build /src/.config /vmlinux.config
