#!/usr/bin/env bash
# Shared by every rootfs image (base/build.sh, postgres/build.sh): build <image-dir>'s Dockerfile as
# <docker-tag>, turn it into <image-dir>/out/rootfs.ext4 (+ .sha256, + .zst) and leave the release
# asset rootfs-<image-name>-<arch>.ext4.zst (+ .sha256) in <image-dir>/out/release/.
#
#   lib/build-rootfs.sh <image-dir> <docker-tag> <image-name>
#   ROOTFS_SIZE=16G lib/build-rootfs.sh ...
#
# Flow: docker build → docker export → mkfs.ext4 -d inside a container (so file ownership and
# modes survive without a loop mount). The output is a sparse file. The mkfs step runs inside the
# image itself, so every image must keep e2fsprogs and tar (base has both).
set -euo pipefail

dir="$(cd "${1:?usage: build-rootfs.sh <image-dir> <docker-tag> <image-name>}" && pwd)"
tag="${2:?usage: build-rootfs.sh <image-dir> <docker-tag> <image-name>}"
name="${3:?usage: build-rootfs.sh <image-dir> <docker-tag> <image-name>}"
out="$dir/out"
size="${ROOTFS_SIZE:-8G}"

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
need_docker

mkdir -p "$out"

step "Building $tag"
docker build -q -t "$tag" "$dir" >/dev/null
ok "image built"

step "Exporting root filesystem"
cid="$(docker create "$tag")"
docker export "$cid" > "$out/rootfs.tar"
docker rm "$cid" >/dev/null
ok "$(du -h "$out/rootfs.tar" | cut -f1) exported"

step "Creating ext4 image ($size)"
docker run --rm -v "$out:/out" -e SIZE="$size" -e UID_GID="$(id -u):$(id -g)" "$tag" bash -euo pipefail -c '
  mkdir /r
  tar -xf /out/rootfs.tar -C /r --numeric-owner --xattrs --xattrs-include="*"
  rm -f /out/rootfs.tar
  # docker export leaves the container marker behind; with it, systemd in the guest believes it
  # runs in a container and skips the sync + read-only remount at shutdown (lost writes, journal
  # recovery on every boot). Same for anything else that says "container".
  rm -f /r/.dockerenv /r/.dockerinit /r/run/.containerenv
  # Docker bind-mounts these during build, so write them here instead of in the Dockerfile.
  # The host (the bridge gateway, by default 172.30.0.1) answers <box>.kvbox and refuses every other
  # name, which sends the resolver straight to 1.1.1.1; if the host does not answer, 1 s later (kvbox #97).
  printf "nameserver 172.30.0.1\nnameserver 1.1.1.1\nnameserver 8.8.8.8\noptions timeout:1\n" > /r/etc/resolv.conf
  printf "127.0.0.1 localhost\n127.0.1.1 kvbox\n::1 localhost ip6-localhost ip6-loopback\n" > /r/etc/hosts
  echo kvbox > /r/etc/hostname
  rm -f /out/rootfs.ext4.tmp
  truncate -s "$SIZE" /out/rootfs.ext4.tmp
  mkfs.ext4 -q -F -L kvbox-root -d /r /out/rootfs.ext4.tmp
  e2fsck -fn /out/rootfs.ext4.tmp >/dev/null
  mv /out/rootfs.ext4.tmp /out/rootfs.ext4
  chown "$UID_GID" /out/rootfs.ext4
'
ok "rootfs.ext4: $(du -h "$out/rootfs.ext4" | cut -f1) used of $size"

step "Checksums and compressed copy"
(cd "$out" && sha256sum rootfs.ext4 > rootfs.ext4.sha256)
if command -v zstd >/dev/null 2>&1; then
  zstd -q -f -T0 -19 --sparse "$out/rootfs.ext4" -o "$out/rootfs.ext4.zst"
  (cd "$out" && sha256sum rootfs.ext4.zst > rootfs.ext4.zst.sha256)
  # Release assets, named as install-server.sh downloads them.
  rel="$out/release"; asset="rootfs-$name-$(uname -m).ext4.zst"
  rm -rf "$rel" && mkdir -p "$rel"
  cp "$out/rootfs.ext4.zst" "$rel/$asset"
  (cd "$rel" && sha256sum "$asset" > "$asset.sha256")
  ok "$asset: $(du -h "$rel/$asset" | cut -f1) (release asset in $rel)"
else
  echo "zstd not found; skipping the compressed copy and release assets"
fi

echo
ok "done: $out/rootfs.ext4"
