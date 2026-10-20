# zbox-images

Guest images for [zbox](https://github.com/ghalex/zbox), self-hosted
Firecracker microVMs. Each directory is one image recipe; the built images
are published as GitHub releases of this repo and downloaded by zbox's
`install.sh`.

| Image | Release tag | Contents |
|---|---|---|
| `base/` | `base-vX.Y.Z` | Ubuntu 24.04, systemd, sshd (key-only), user `zbox` with passwordless sudo, curl, git |

## How an image works

The image is an ext4 root filesystem. Nothing per-box is baked in: at boot,
zbox passes the IP (`ip=`), hostname (`zbox.name=`) and the authorized SSH
public key (`zbox.sshkey=`, base64) on the kernel command line, and a
first-boot `zbox-init.service` applies them and generates per-box SSH host
keys before sshd starts. One image serves every host and user.

## Build

Needs Docker; no root and no loop mount on the host.

```
base/build.sh                 # -> base/out/rootfs.ext4 (2 GiB sparse, ~290 MB used), .sha256, .zst
ROOTFS_SIZE=4G base/build.sh  # larger disk
```

The build runs `docker build`, `docker export`, then `mkfs.ext4 -d` inside a
container so ownership, setuid bits and capabilities survive.

Use a local build with zbox's installer instead of downloading:

```
ZBOX_IMAGES_DIR=~/projects/zbox-images ./install.sh
```

## Release

```
./release.sh base v0.1.0      # builds, then publishes release base-v0.1.0 with the .zst and its sha256
```

zbox pins the version it installs (`ROOTFS_VERSION` in `install.sh`).

## License

MIT
