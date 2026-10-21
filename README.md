# kvbox-images

Guest images and the guest kernel for [kvbox](https://github.com/ghalex/kvbox),
self-hosted Firecracker microVMs. Each directory is one recipe; the builds are
published as GitHub releases of this repo and downloaded by kvbox's
`install-server.sh`.

| Image | Release tag | Contents |
|---|---|---|
| `base/` | `base-vX.Y.Z` | Ubuntu 24.04, systemd, sshd (key-only), user `kvbox` with passwordless sudo, curl, git, Python 3, Node.js 22 (npm), Docker Engine, Claude Code CLI |
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

## Build

Needs Docker; no root and no loop mount on the host.

```
base/build.sh                 # -> base/out/rootfs.ext4 (8 GiB sparse, ~1.2 GB used), .sha256, .zst
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
./release.sh base v0.2.0        # builds, then publishes release base-v0.2.0
./release.sh kernel v6.1.190-1  # builds, then publishes release kernel-v6.1.190-1
```

kvbox pins the versions it installs (`ROOTFS_VERSION` and `KERNEL_VERSION` in
`install-server.sh`).

## License

MIT
