#!/usr/bin/env bash
# Build the kvbox base image: base/out/rootfs.ext4 (+ .sha256, + .zst) and base/out/release/ assets.
#
#   base/build.sh                   # needs Docker; no root on the host
#   ROOTFS_SIZE=16G base/build.sh
#
# Flow (lib/build-rootfs.sh): docker build → docker export → mkfs.ext4 -d inside a container (so
# file ownership and modes survive without a loop mount). The output is a sparse file: 8 GiB of
# disk, about 1.9 GB on the host.
#
# Boot it with (install.sh / kvbox fill these in):
#   console=ttyS0 reboot=k panic=1 init=/sbin/overlay-init kvbox.overlay=/dev/vdb
#     (Firecracker appends pci=off root=/dev/vda ro itself; /dev/vdb is the box's own ext4 disk,
#      see rootfs/sbin/overlay-init; without kvbox.overlay= the image boots straight from vda rw)
#   ip=<ip>::<gw>:255.255.255.0::eth0:off kvbox.name=<name> kvbox.sshkey=<base64 pubkey>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../lib/build-rootfs.sh" "$here" kvbox-base:local base
