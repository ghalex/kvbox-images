# kvbox-images

Guest images and the guest kernel for [kvbox](https://github.com/ghalex/kvbox),
self-hosted Firecracker microVMs. Each directory is one recipe; the builds are
published as GitHub releases of this repo and downloaded by kvbox's
`install-server.sh`.

| Image | Release tag | Contents |
|---|---|---|
| `base/` | `base-vX.Y.Z` | Ubuntu 24.04, systemd, sshd (key-only), user `kvbox` with passwordless sudo, curl, git, Python 3, uv (`uv`, `uvx`), Node.js 22 (npm), Docker Engine, nginx (off; `kvbox deploy` turns it on to serve `/srv/app/dist`), Claude Code CLI, [agent-browser](https://agent-browser.dev) with a headless Chrome (Chrome for Testing in `/opt/chrome`, also `chromium` on PATH; `AGENT_BROWSER_EXECUTABLE_PATH` points at it in every SSH session) |
| `kernel/` | `kernel-vX.Y.Z-N` | Linux 6.1 LTS (`X.Y.Z`) with Firecracker's CI config plus `kernel/kvbox.config`; `N` is the recipe revision |

## Why our own kernel

Firecracker publishes CI kernels, but their config leaves out the netfilter
tables Docker needs (the `raw` table, nf_tables), so no container with
networking could start. `kernel/` builds the same Linux 6.1 LTS from
kernel.org with that CI config as the base (`firecracker-ci-x86_64-6.1.config`,
extracted from Firecracker's own build) and the additions in `kvbox.config`:
Docker's netfilter requirements, nf_tables, a few network drivers, FUSE,
`/proc/config.gz`. x86_64 only for now.

## How an image works

The image is an ext4 root filesystem. Nothing per-box is baked in: at boot,
kvbox passes the IP (`ip=`), hostname (`kvbox.name=`) and the authorized SSH
public key (`kvbox.sshkey=`, base64) on the kernel command line, and a
first-boot `kvbox-init.service` applies them and generates per-box SSH host
keys before sshd starts. One image serves every host and user.

A box restored from a snapshot (`kvbox new --from`) wakes up with the source
box's name, address and clock still in memory, so the image also runs
`kvbox-agent.service`: a small Python service listening on vsock port 52 (a
direct host-to-guest channel, independent of the box's network). kvbox connects
to it right after the restore and sends one JSON line with the new identity
(`{"op": "identity", "name", "ip", "prefixLen", "gateway", "mac", "time"}`); the
agent renames the box, re-addresses `eth0` and sets the clock, then answers
`{"ok": true}`. `{"op": "ping"}` answers with the hostname.
`{"op": "authorizedKeys", "lines": [...]}` replaces the `kvbox` user's
`authorized_keys` with exactly those lines (base v0.6.0 and later): a restored
or woken box has the file it was frozen with, and the host sends the current
one, its own key plus the lines the control plane gave the box, so a new SSH
CA reaches a box without a cold boot.
`{"op": "stats"}` (base v0.7.0 and later) answers with the box's own load
average, CPU count, memory (used is total minus available), root disk (the
overlay, so the box's own writes) and uptime, read from `/proc` and `statvfs`;
`kvbox vm top` shows it.
`{"op": "dropVolumes"}` (base v0.9.0 and later) force-unmounts every volume
(see below) the box still has mounted and answers with the paths: a box
restored from a snapshot has the source box's mounts in memory, but the host
gives it an empty placeholder disk instead of the volume, so the mounts are dead.

A volume (kvbox issue #52) is an extra disk the host attaches, `/dev/vdc` and
up, formatted ext4 on the host with the label `kvbox:<name>`. At boot
`kvbox-volumes.service` (base v0.9.0 and later) mounts each labelled disk at
`/mnt/<name>`, owned by the `kvbox` user; nothing is written to fstab, since
which volumes a box has is the host's knowledge, sent as drives at every boot.

One image file also serves every box on a host: kvbox attaches it read-only
as `/dev/vda` and gives each box its own small ext4 as `/dev/vdb`. The kernel
starts `/sbin/overlay-init` (`init=/sbin/overlay-init kvbox.overlay=/dev/vdb`),
which stacks the box disk on the base as an overlayfs, makes that the root and
only then starts systemd. Everything the box writes lands on its own disk; the
base is never modified, so a new box costs a few MB instead of a copy of the
image. Docker's storage lives in a plain directory of the box disk (bind-mounted
to `/var/lib/docker`) because overlay2 cannot run on top of an overlayfs.
Booted without `kvbox.overlay=`, the image works the old way, as a plain
writable root.

## Build

Needs Docker; no root and no loop mount on the host.

```
base/build.sh                 # -> base/out/rootfs.ext4 (8 GiB sparse, ~1.9 GB used), .sha256, .zst
ROOTFS_SIZE=16G base/build.sh # larger disk
kernel/build.sh               # -> kernel/out/vmlinux (several minutes the first time, cached after)
```

The image build runs `docker build`, `docker export`, then `mkfs.ext4 -d`
inside a container so ownership, setuid bits and capabilities survive. The
kernel build compiles inside a container too and copies out only `vmlinux`.
Each build leaves its release assets in `<recipe>/out/release/`.

Use local builds with kvbox's installer instead of downloading:

```
KVBOX_IMAGES_DIR=~/projects/kvbox-images ./install-server.sh
```

## Release

```
./release.sh base v0.4.0        # builds, then publishes release base-v0.4.0
./release.sh kernel v6.1.190-1  # builds, then publishes release kernel-v6.1.190-1
```

kvbox pins the versions it installs (`ROOTFS_VERSION` and `KERNEL_VERSION` in
`install-server.sh`).

## License

MIT
