# kvbox-images

Guest images and the guest kernel for [kvbox](https://github.com/ghalex/kvbox),
self-hosted Firecracker microVMs. Each directory is one recipe; the builds are
published as GitHub releases of this repo and downloaded by kvbox's
`install-server.sh`.

| Image | Release tag | Contents |
|---|---|---|
| `base/` | `base-vX.Y.Z` | Ubuntu 24.04, systemd, sshd (key-only), user `kvbox` with passwordless sudo, curl, git, Python 3, uv (`uv`, `uvx`), Node.js 22 (npm), Docker Engine, nginx (off; `kvbox deploy` turns it on to serve `/srv/app/dist`), Claude Code CLI, [agent-browser](https://agent-browser.dev) with a headless Chrome (Chrome for Testing in `/opt/chrome`, also `chromium` on PATH; `AGENT_BROWSER_EXECUTABLE_PATH` points at it in every SSH session) |
| `postgres/` | `postgres-vX.Y.Z` | Everything in `base` plus Ubuntu's PostgreSQL (16 on 24.04) listening on every address, password (scram-sha-256) logins from anywhere; the role, database and password come from the box's environment (see [The postgres image](#the-postgres-image)) |
| `gh-runner/` | `gh-runner-vX.Y.Z` | Everything in `base` plus GitHub's Actions runner in `/home/kvbox/actions-runner` and `xz-utils zstd unzip zip jq`; registered at first boot from the box's environment (see [The gh-runner image](#the-gh-runner-image)) |
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
`{"op": "env", "vars": [["NAME", "value"], ...]}` (base v0.10.0 and later)
replaces the box owner's environment variables (kvbox issue #88), sent by the
host at every boot and after a restore. The agent writes them twice, each in the
form its reader takes literally: `/etc/kvbox/env` for systemd's
`EnvironmentFile=` (double-quoted, `\` and `"` escaped; `kvbox deploy`'s
`kvbox-app` unit reads it and is restarted when the list changed) and the
`kvbox` user's `~/.ssh/environment` for sshd (`PermitUserEnvironment yes`), so
every SSH session, `kvbox exec` included, has them. It answers with the count
and whether anything changed. Values are single lines. After every successful
`env` the agent also touches `/run/kvbox/env-ready` (base v0.12.0 and later;
`/run` is a tmpfs, so the file is absent at each boot until the host's first
push): a unit that needs the owner's variables waits for it.

A volume (kvbox issue #52) is an extra disk the host attaches, `/dev/vdc` and
up, formatted ext4 on the host with the label `kv:<name>` (an ext4 label is 16 bytes). At boot
`kvbox-volumes.service` (base v0.9.1 and later) mounts each labelled disk at
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

## The postgres image

`postgres/` (kvbox issue #87) is `FROM kvbox-base:local` plus Ubuntu's
`postgresql` package. The cluster is created at build time with
`listen_addresses = '*'` and `pg_hba.conf` allowing `host all all 0.0.0.0/0`
and `::/0` with scram-sha-256: the host firewall decides who reaches a box
(boxes are isolated unless linked). `postgresql.service` starts at boot.

The image tells the host how to treat it in `/etc/kvbox/image.json`, which the
host reads from the image file without booting it (`debugfs -R "cat
/etc/kvbox/image.json"`); the base image has none:

```json
{
  "autoHibernate": false,
  "env": { "POSTGRES_USER": "postgres", "POSTGRES_DB": "${POSTGRES_USER}" },
  "generate": ["POSTGRES_PASSWORD"],
  "connect": "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${BOX}.kvbox:5432/${POSTGRES_DB}"
}
```

- `autoHibernate`: whether the host may hibernate the box when idle.
- `env`: defaults for variables the user did not give; a value may refer to
  another variable as `${NAME}`.
- `generate`: variables the host fills with a random password when the user
  gave none.
- `connect`: printed by the host after `kvbox new`, with `${...}` expanded
  (`${BOX}` is the box name).
- `idle` (optional, kvbox #102): a script in the box that exits 0 when the box
  is idle; a new box's idle check (the host keeps it, `kvbox vm set
  --idle-check` changes it), which auto-hibernate asks through kvbox-agent's
  `idle` (base v0.12.0 and later) instead of watching network traffic. `autoHibernate` may also
  be a duration (`"10m"`), a new box's idle time.

So the box always receives `POSTGRES_USER`, `POSTGRES_DB` and
`POSTGRES_PASSWORD` through kvbox-agent's `env`. `kvbox-postgres-init.service`
runs at every boot until `/var/lib/kvbox/postgres-init.done` exists: it waits
for `/run/kvbox/env-ready` (up to 5 minutes), reads the three variables from
`/etc/kvbox/env` (parsed, never sourced), creates the role (`LOGIN CREATEDB`)
unless it exists, sets its password, creates the database owned by it unless
it exists, then writes the marker. Without a password it does nothing and
leaves no marker, so a later boot retries. Its log is
`journalctl -u kvbox-postgres-init`.

```
kvbox new mydb --base postgres -e POSTGRES_PASSWORD=x -e POSTGRES_USER=me -e POSTGRES_DB=app
```

## The gh-runner image

`gh-runner/` (kvbox issue #100) is `FROM kvbox-base:local` plus GitHub's
Actions runner (`ARG RUNNER_VERSION`, it updates itself after that), its
dependencies (`bin/installdependencies.sh`) and a few tools GitHub's
`ubuntu-latest` has and actions expect (`xz-utils zstd unzip zip jq`). Docker
comes from base.

```json
{
  "autoHibernate": "10m",
  "idle": "/usr/local/sbin/kvbox-idle",
  "env": { "GITHUB_RUNNER_LABELS": "kvbox" },
  "connect": "${GITHUB_URL}/settings/actions/runners"
}
```

The runner keeps a long poll open to GitHub, so network traffic never says
the box is idle. `idle` (kvbox issue #102) names the script a new box's host asks
instead, through kvbox-agent's `idle` request: `kvbox-idle` exits 0 while no
`Runner.Worker` process runs (one exists only during a job). `autoHibernate`
gives a new box 10 minutes of that before it hibernates. `kvbox-gh-runner-init.service` runs at every boot
until `/var/lib/kvbox/gh-runner-init.done` exists: it waits for
`/run/kvbox/env-ready`, reads `GITHUB_URL`, `GITHUB_RUNNER_TOKEN` (the
registration token from the repo's Settings → Actions → Runners → New
self-hosted runner, single-use, valid for an hour), `GITHUB_RUNNER_NAME`
(default: the box name) and `GITHUB_RUNNER_LABELS`, runs `config.sh
--unattended --replace` as kvbox unless `.runner` exists, installs the runner's
systemd service with `svc.sh` unless `.service` exists, starts it and writes
the marker. The runner service is enabled, so it is back after every boot.
Without a URL or token it does nothing and leaves no marker. Its log is
`journalctl -u kvbox-gh-runner-init`.

```
kvbox new ci --base gh-runner -e GITHUB_URL=https://github.com/<owner>/<repo> -e GITHUB_RUNNER_TOKEN=<token>
```

## Build

Needs Docker; no root and no loop mount on the host.

```
base/build.sh                 # -> base/out/rootfs.ext4 (8 GiB sparse, ~1.9 GB used), .sha256, .zst
ROOTFS_SIZE=16G base/build.sh # larger disk
postgres/build.sh             # -> postgres/out/rootfs.ext4; builds base's Dockerfile first (kvbox-base:local)
gh-runner/build.sh            # -> gh-runner/out/rootfs.ext4; same
kernel/build.sh               # -> kernel/out/vmlinux (several minutes the first time, cached after)
```

The image build (`lib/build-rootfs.sh`, shared by every rootfs image) runs
`docker build`, `docker export`, then `mkfs.ext4 -d` inside a container so ownership, setuid bits and capabilities survive. The
kernel build compiles inside a container too and copies out only `vmlinux`.
Each build leaves its release assets in `<recipe>/out/release/`.

Use local builds with kvbox's installer instead of downloading:

```
KVBOX_IMAGES_DIR=~/projects/kvbox-images ./install-server.sh
```

## Release

```
./release.sh base v0.4.0        # builds, then publishes release base-v0.4.0
./release.sh postgres v0.1.0    # builds, then publishes release postgres-v0.1.0 (rootfs-postgres-<arch>.ext4.zst)
./release.sh kernel v6.1.190-1  # builds, then publishes release kernel-v6.1.190-1
```

kvbox pins the versions it installs (`ROOTFS_VERSION` and `KERNEL_VERSION` in
`install-server.sh`).

## License

MIT
