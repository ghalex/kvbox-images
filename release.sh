#!/usr/bin/env bash
# Build an image and publish it as a GitHub release of this repo.
#
#   ./release.sh base v0.1.0        # -> release "base-v0.1.0" with rootfs-base-<arch>.ext4.zst + .sha256
#
# Needs: docker, zstd, gh (logged in with push access to this repo).
set -euo pipefail

image="${1:?usage: release.sh <image> <version>}"
version="${2:?usage: release.sh <image> <version>}"
arch="$(uname -m)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tag="${image}-${version}"
asset="rootfs-${image}-${arch}.ext4.zst"

[[ -d "$here/$image" ]] || { echo "no such image: $image" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }

"$here/$image/build.sh"

rel="$here/$image/out/release"
rm -rf "$rel" && mkdir -p "$rel"
cp "$here/$image/out/rootfs.ext4.zst" "$rel/$asset"
(cd "$rel" && sha256sum "$asset" > "$asset.sha256")

notes="$(printf '%s image %s for %s.\n\nInstall with kvbox: `install.sh` downloads this asset, verifies the checksum and unpacks it to `~/.kvbox/assets/rootfs.ext4`.\n\n```\nROOTFS_VERSION=%s ./install.sh\n```' "$image" "$version" "$arch" "$version")"

if gh release view "$tag" --repo ghalex/kvbox-images >/dev/null 2>&1; then
  gh release upload "$tag" "$rel/$asset" "$rel/$asset.sha256" --clobber --repo ghalex/kvbox-images
else
  gh release create "$tag" "$rel/$asset" "$rel/$asset.sha256" --repo ghalex/kvbox-images --title "$tag" --notes "$notes"
fi
echo "published $tag: $asset"
