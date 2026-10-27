#!/usr/bin/env bash
# Build an image and publish it as a GitHub release of this repo.
#
#   ./release.sh base v0.1.0        # -> release "base-v0.1.0" with rootfs-base-<arch>.ext4.zst + .sha256
#   ./release.sh kernel v6.1.190-1  # -> release "kernel-v6.1.190-1" with vmlinux-<arch> + .sha256
#
# <image>/build.sh builds and leaves the assets, named as install-server.sh expects them, in
# <image>/out/release/; this script uploads that directory.
#
# Needs: docker, zstd, gh (logged in with push access to this repo).
set -euo pipefail

image="${1:?usage: release.sh <image> <version>}"
version="${2:?usage: release.sh <image> <version>}"
arch="$(uname -m)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tag="${image}-${version}"

[[ -d "$here/$image" ]] || { echo "no such image: $image" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }

"$here/$image/build.sh"

rel="$here/$image/out/release"
[[ -d "$rel" ]] && [[ -n "$(ls -A "$rel")" ]] || { echo "$image/build.sh left no release assets in $rel" >&2; exit 1; }
assets=("$rel"/*)

case "$image" in
  base)   what="Base guest image $version ($arch): Ubuntu 24.04 with Python 3, Node.js 22, Docker, nginx (for kvbox deploy), Claude Code and kvbox-agent (vsock control channel for snapshot restores)."
          how="ROOTFS_VERSION=$version ./install-server.sh" ;;
  kernel) what="Guest kernel $version ($arch): Linux $(cat "$here/kernel/out/vmlinux.version") with Firecracker's CI config plus kernel/kvbox.config (netfilter for Docker, nf_tables, FUSE)."
          how="KERNEL_VERSION=${version#v} ./install-server.sh" ;;
  *)      what="$image $version ($arch)."; how="./install-server.sh" ;;
esac
# shellcheck disable=SC2016  # the backticks are markdown, not command substitution
notes="$(printf '%s\n\nInstall with kvbox: `install-server.sh` downloads the asset, verifies the checksum and puts it in `~/.kvbox/assets`.\n\n```\n%s\n```' "$what" "$how")"

if gh release view "$tag" --repo ghalex/kvbox-images >/dev/null 2>&1; then
  gh release upload "$tag" "${assets[@]}" --clobber --repo ghalex/kvbox-images
else
  gh release create "$tag" "${assets[@]}" --repo ghalex/kvbox-images --title "$tag" --notes "$notes"
fi
echo "published $tag: $(basename -a "${assets[@]}" | tr '\n' ' ')"
