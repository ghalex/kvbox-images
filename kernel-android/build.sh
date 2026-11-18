#!/usr/bin/env bash
# Build the android guest kernel: kernel/'s recipe with kernel/android.config (binder) merged on top.
# Leaves kernel-android/out/vmlinux (+ .sha256) and kernel-android/out/release/vmlinux-android-<arch>.
#
#   kernel-android/build.sh         # needs Docker (BuildKit); shares kernel/'s download layer
#
# Released as kernel-android-vX.Y.Z-N, beside kernel-vX.Y.Z-N. Only a box of an image whose
# image.json says "kernel": "android" boots it (the android image); kvbox's install-server.sh puts it
# at ~/.kvbox/assets/vmlinux-android.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_CONFIGS="kvbox.config android.config" KERNEL_OUT="$here/out" KERNEL_ASSET=vmlinux-android \
  exec "$here/../kernel/build.sh"
