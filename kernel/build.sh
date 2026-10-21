#!/usr/bin/env bash
# Build the kvbox guest kernel: kernel/out/vmlinux (+ .sha256) and kernel/out/release/ assets.
#
#   kernel/build.sh                 # needs Docker (BuildKit); ~5-10 minutes, cached afterwards
#
# Flow: a Docker build fetches the pinned Linux 6.1 tarball from kernel.org, merges
# firecracker-ci-x86_64-6.1.config with kvbox.config and compiles vmlinux; the output stage
# is copied to out/. x86_64 only for now.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/out"
arch="$(uname -m)"

# Pinned Linux release and the sha256 of its tarball (from kernel.org's sha256sums.asc).
KERNEL_VERSION="${KERNEL_VERSION:-6.1.190}"
KERNEL_SHA256="${KERNEL_SHA256:-8aa50daca0412a3d0a61a87af3744f39773d40b3132635fb7bc9be652cdb7b0c}"

if [[ -t 1 ]]; then BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; NC=$'\033[0m'; else BOLD=""; GREEN=""; RED=""; NC=""; fi
step() { printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

[[ "$arch" == x86_64 ]] || fail "the kvbox kernel recipe only covers x86_64 for now (this is $arch)"
command -v docker >/dev/null 2>&1 || fail "docker is required to build the kernel"
docker info >/dev/null 2>&1 || fail "docker daemon is not running (or you are not in the docker group)"

mkdir -p "$out"
rm -f "$out"/vmlinux "$out"/vmlinux.* "$out"/release/*

step "Building Linux $KERNEL_VERSION with kvbox.config (first build takes a few minutes)"
# The output stage is streamed out as a tar so the files end up owned by the caller
# (BuildKit's directory exporter tries to chown them to root and fails for a normal user).
docker build -q --target out --output type=tar,dest=- \
  --build-arg KERNEL_VERSION="$KERNEL_VERSION" --build-arg KERNEL_SHA256="$KERNEL_SHA256" \
  "$here" | tar -xf - -C "$out" vmlinux vmlinux.config
[[ -s "$out/vmlinux" ]] || fail "the build produced no vmlinux"
ok "vmlinux: $(du -h "$out/vmlinux" | cut -f1)"

step "Checksum and release assets"
(cd "$out" && sha256sum vmlinux > vmlinux.sha256)
rel="$out/release"
rm -rf "$rel" && mkdir -p "$rel"
cp "$out/vmlinux" "$rel/vmlinux-$arch"
(cd "$rel" && sha256sum "vmlinux-$arch" > "vmlinux-$arch.sha256")
echo "$KERNEL_VERSION" > "$out/vmlinux.version"
ok "release assets in $rel"

echo
ok "done: $out/vmlinux (Linux $KERNEL_VERSION)"
