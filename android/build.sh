#!/usr/bin/env bash
# Build the kvbox android image: android/out/rootfs.ext4 (+ .sha256, + .zst) and
# android/out/release/rootfs-android-<arch>.ext4.zst (+ .sha256).
#
#   android/build.sh                     # needs Docker; no root on the host
#   ROOTFS_SIZE=12G android/build.sh
#
# The image is FROM kvbox-base:local, so the base Dockerfile is built first (cached when unchanged).
# It boots the android kernel (kernel-android/, binder built in), not the usual one: image.json says so.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$here/../lib/common.sh"
need_docker

step "Building kvbox-base:local (the android image starts from it)"
docker build -q -t kvbox-base:local "$here/../base" >/dev/null
ok "base image built"

ROOTFS_SIZE="${ROOTFS_SIZE:-10G}" exec "$here/../lib/build-rootfs.sh" "$here" kvbox-android:local android
