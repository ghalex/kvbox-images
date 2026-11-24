#!/usr/bin/env bash
# Build the kvbox registry image (kvbox #234): registry/out/rootfs.ext4 (+ .sha256, + .zst) and
# registry/out/release/rootfs-registry-<arch>.ext4.zst (+ .sha256).
#
#   registry/build.sh                   # needs Docker; no root on the host
#   ROOTFS_SIZE=16G registry/build.sh
#
# The image is FROM kvbox-base:local, so the base Dockerfile is built first (cached when unchanged).
# Boots exactly like base (see base/build.sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$here/../lib/common.sh"
need_docker

step "Building kvbox-base:local (the registry image starts from it)"
docker build -q -t kvbox-base:local "$here/../base" >/dev/null
ok "base image built"

exec "$here/../lib/build-rootfs.sh" "$here" kvbox-registry:local registry
