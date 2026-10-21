#!/usr/bin/env bash
# Build the kvbox base image: base/out/rootfs.ext4 (+ .sha256, + .zst) and base/out/release/ assets.
#
#   base/build.sh                   # needs Docker; no root on the host
#   ROOTFS_SIZE=16G base/build.sh
#
# Flow: docker build → docker export → mkfs.ext4 -d inside a container (so file
# ownership and modes survive without a loop mount). The output is a sparse
# file: 8 GiB of disk, about 1.9 GB on the host.
#
# Boot it with (install.sh / kvbox fill these in):
#   console=ttyS0 reboot=k panic=1          (Firecracker appends pci=off root=/dev/vda rw itself)
#   ip=<ip>::<gw>:255.255.255.0::eth0:off kvbox.name=<name> kvbox.sshkey=<base64 pubkey>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/out"
size="${ROOTFS_SIZE:-8G}"
tag="kvbox-base:local"

if [[ -t 1 ]]; then BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; NC=$'\033[0m'; else BOLD=""; GREEN=""; RED=""; NC=""; fi
step() { printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker is required to build the base image"
docker info >/dev/null 2>&1 || fail "docker daemon is not running (or you are not in the docker group)"

mkdir -p "$out"

step "Building $tag"
docker build -q -t "$tag" "$here" >/dev/null
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
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /r/etc/resolv.conf
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
  rel="$out/release"; asset="rootfs-base-$(uname -m).ext4.zst"
  rm -rf "$rel" && mkdir -p "$rel"
  cp "$out/rootfs.ext4.zst" "$rel/$asset"
  (cd "$rel" && sha256sum "$asset" > "$asset.sha256")
  ok "$asset: $(du -h "$rel/$asset" | cut -f1) (release asset in $rel)"
else
  echo "zstd not found; skipping the compressed copy and release assets"
fi

echo
ok "done: $out/rootfs.ext4"
