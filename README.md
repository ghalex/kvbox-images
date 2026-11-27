# kvbox-images

Guest images and the guest kernel for [kvbox](https://github.com/ghalex/kvbox),
self-hosted Firecracker microVMs. Each directory is one recipe; the builds are
published as GitHub releases of this repo and downloaded by kvbox's
`install-server.sh`.

| Image | Release tag | Contents |
|---|---|---|
| `base/` | `base-vX.Y.Z` | Ubuntu 24.04, systemd, sshd (key-only), user `kvbox` with passwordless sudo, curl, git, Python 3, uv (`uv`, `uvx`), Node.js 22 (npm), Docker Engine, GitHub's CLI (`gh`), nginx (off; `kvbox deploy` turns it on to serve `/srv/app/dist`), Claude Code CLI, [agent-browser](https://agent-browser.dev) with a headless Chrome (Chrome for Testing in `/opt/chrome`, also `chromium` on PATH; `AGENT_BROWSER_EXECUTABLE_PATH` points at it in every SSH session) |
| `postgres/` | `postgres-vX.Y.Z` | Everything in `base` plus PostgreSQL 18 and pgvector from the PostgreSQL project's apt repository (PGDG), listening on every address with its own TLS certificate, password (scram-sha-256) logins from anywhere; the role, database, password and optionally a data directory on a volume come from the box's environment (see [The postgres image](#the-postgres-image)) |
| `redis/` | `redis-vX.Y.Z` | Everything in `base` plus [Valkey](https://valkey.io) 9.1 (BSD, speaks the Redis protocol) from the Valkey project's own build for Ubuntu 24.04, plain on 6379 and TLS on 6380 with its own certificate, append-only file persistence; the password and optionally a data directory on a volume come from the box's environment (see [The redis image](#the-redis-image)) |
| `garage/` | `garage-vX.Y.Z` | Everything in `base` plus [Garage](https://garagehq.deuxfleurs.fr) 2.5 (AGPL, speaks the S3 protocol) from the Garage project's own static build, one node on port 3900 (S3) and 3902 (public buckets, no signature) with its data on a volume; what kvbox's Object Storage runs on (see [The garage image](#the-garage-image)) |
| `registry/` | `registry-vX.Y.Z` | Everything in `base` plus [zot](https://zotregistry.dev) 2.1 (Apache 2.0, an OCI registry: `docker push` and `docker pull`) from the zot project's own static build, on port 5000 behind one login, its images on a volume; what kvbox's container registry runs on (see [The registry image](#the-registry-image)) |
| `k3s/` | `k3s-vX.Y.Z` | Everything in `base` plus [k3s](https://k3s.io) 1.37 (Apache 2.0, Kubernetes) from the k3s project's own release, with the images it needs to come up baked in; one image for a cluster's server and its nodes, the role and the join token come from the box's environment; what kvbox's managed Kubernetes runs on (see [The k3s image](#the-k3s-image)) |
| `gh-runner/` | `gh-runner-vX.Y.Z` | Everything in `base` plus GitHub's Actions runner in `/home/kvbox/actions-runner` and `xz-utils zstd unzip zip jq`; registered at first boot from the box's environment (see [The gh-runner image](#the-gh-runner-image)) |
| `android/` | `android-vX.Y.Z` | Everything in `base` plus Java 17, Maven, the Android SDK's command-line tools, platform-tools (adb) and build-tools, Appium with the UiAutomator2 driver; Android itself runs as a [Redroid](https://github.com/remote-android/redroid-doc) container started at boot. Boots the android kernel (see [The android image](#the-android-image)) |
| `kernel/` | `kernel-vX.Y.Z-N` | Linux 6.1 LTS (`X.Y.Z`) with Firecracker's CI config plus `kernel/kvbox.config`; `N` is the recipe revision |
| `kernel-android/` | `kernel-android-vX.Y.Z-N` | The same kernel plus `kernel/android.config` (binder); booted only by boxes of an image that asks for it |

## Integrations

An integration (kvbox issue #205) is an account the box's owner connected once
in the kvbox web app (GitHub, Claude Code) and turned on for a box
(`kvbox vm set <box> --integration github`). Nothing of it is written into the
box: a program asks the host each time it needs the credential, so a disconnect
works at once and a snapshot, a fork or a backup carries no secret. From base
v0.17.0:

- `kvbox-credential <integration>` asks the host over vsock (host CID 2, port
  53, the one direction where the box opens the connection; one JSON line each
  way) and prints the answer: `{"ok": true, "kind", "token", "identity"?}` or
  `{"ok": false, "code", "message"}` with `off`, `not-connected`,
  `needs-reconnect` or `unavailable` (exit 0, 3, 4, 5, 6). `--token` prints the
  token alone. Any user in the box may ask.
- git: `/etc/gitconfig` names `/usr/local/lib/kvbox/git-credential-kvbox` as
  the credential helper for `https://github.com`. It answers with the token, and
  stays silent when there is none, so the user's own helpers and logins work as
  in any box. While GitHub is on for the box, kvbox-agent keeps
  `/etc/kvbox/gitconfig` (included by `/etc/gitconfig`): `git@github.com:` and
  `ssh://git@github.com/` URLs go over HTTPS, and the connected account's name
  and email are who commits; a user's own `~/.gitconfig` wins over both.
- `gh`: `/usr/local/bin/gh` is ahead of GitHub's CLI (`/usr/bin/gh`, from
  GitHub's apt repository) on PATH. With no `GH_TOKEN` or `GITHUB_TOKEN` set and
  a token answered, it runs the real one with `GH_TOKEN`; otherwise untouched,
  so `gh auth login` works too.
- `claude` (base v0.18.0): `/usr/local/bin/claude` is a wrapper ahead of the
  real one (`~/.local/bin/claude`, which the image's `~/.profile` puts last on
  PATH, so Claude Code's self-updates never replace the wrapper). With no
  `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` set and a credential
  answered, it runs the real one with the `claude setup-token` token as
  `CLAUDE_CODE_OAUTH_TOKEN` or the API key as `ANTHROPIC_API_KEY`; otherwise
  untouched, so a login inside the box works too. While Claude Code is on,
  kvbox-agent marks `~/.claude.json` as onboarded so the first start goes
  straight in.

GitHub is github.com only. The host side is the kvbox-server release after 0.6.12; under an older
one every answer is `unavailable` and the box behaves as it did before.

## Why our own kernel

Firecracker publishes CI kernels, but their config leaves out the netfilter
tables Docker needs (the `raw` table, nf_tables), so no container with
networking could start. `kernel/` builds the same Linux 6.1 LTS from
kernel.org with that CI config as the base (`firecracker-ci-x86_64-6.1.config`,
extracted from Firecracker's own build) and the additions in `kvbox.config`:
Docker's netfilter requirements, nf_tables, a few network drivers, FUSE,
`/proc/config.gz`, and what Kubernetes writes its rules with (the `statistic`,
`physdev`, `recent` and `limit` matches, NFLOG, ipsets, a minimal IPVS, plus the
matches other network plugins and service meshes use). x86_64 only for now.

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
units read it: `kvbox-app` of one app, `kvbox-<service>` of a stack; when the
list changed, every `kvbox-*` unit in `/etc/systemd/system` whose file names
one of the two variable files is restarted if it runs, base v0.13.0 and later,
only `kvbox-app` before; a stack's database reads neither and is left alone) and the
`kvbox` user's `~/.ssh/environment` for sshd (`PermitUserEnvironment yes`), so
every SSH session, `kvbox exec` included, has them. It answers with the count
and whether anything changed. Values are single lines. After every successful
`env` the agent also touches `/run/kvbox/env-ready` (base v0.12.0 and later;
`/run` is a tmpfs, so the file is absent at each boot until the host's first
push): a unit that needs the owner's variables waits for it.
`{"op": "script", "path": "/usr/local/sbin/…", "input": <any JSON>}` (base
v0.14.0 and later, kvbox issue #173) runs a script the image names in its
`image.json` (`scripts`) as root, with `input` as one JSON line on stdin (never
argv: it may hold a password), for at most 30 seconds, and answers
`{"ok": true, "output": <the JSON the script printed>}`; a non-zero exit is an
error carrying the script's last stderr line. It is how the host asks an image
something only the image knows, such as a managed Postgres's status.
`{"op": "run", "id": "…", "command": "node ~/app/embed.js", "timeoutSec": 600}`
(base v0.15.0 and later, kvbox issue #190) starts a command of the box owner's
and answers at once with `{"ok": true, "started": true}` (`false` when that id
was already started); `{"op": "runStatus", "id": "…"}` then answers `running`,
`exited` with `exitCode`, `timeout` or `unknown`. The command is a transient
systemd unit `kvbox-run-<id>.service`: the `kvbox` user, its home, a login
shell, the owner's variables, everything it started killed at the deadline.
Its output is `/var/log/kvbox/runs/<id>.out` (stdout) and `<id>.err` (stderr),
base v0.16.0 and later (one `<id>.log` with both before); the newest 50 runs of
each kind are kept, the kind being the id's prefix (`cron-<n>`, `ex_<hex>`), so
execs never push out a cron run nobody has read yet. A reboot forgets a run (`unknown`). It is what a cron trigger with a
command runs, and what kvbox's `exec` over the API (kvbox issue #188) runs.
`{"op": "runOutput", "id": "…", "stream": "stdout", "offset": 0, "limit": 1048576}`
(base v0.16.0 and later) reads a run's output back: at most 1 MiB from `offset`
of `stdout` or `stderr`, answered as `{"ok": true, "size", "offset", "data"}`
with `data` in base64 (a command may print bytes that are not UTF-8, and a cut
may fall inside a character) and `size` the stream's whole length, so the asker
knows what it did not get. No file is size 0, never an error. A run from base
v0.15.x has only the `.log`: it reads as stdout, with stderr empty.

`{"op": "integrations", "list": ["github"], "identity": {"name", "email"}}`
(base v0.17.0 and later, kvbox issue #205) is the list of integrations turned
on for the box, sent whenever it changes and each time the box comes up; it
never holds a credential (see [Integrations](#integrations)). From base
v0.18.0 the answer's `known` lists the integrations the image can use, so the
host refuses one it cannot.

`{"op": "freeze", "box": true, "volumes": ["data"], "thawAfterSec": 30}` and
`{"op": "thaw"}` (base v0.19.0 and later, kvbox issue #211) make a backup's
copy of a disk clean. The host copies a disk's file from outside the box, so
writes the guest still holds in memory would be missing, as after a power cut.
`freeze` writes them out and blocks new writes (`FIFREEZE`, what `fsfreeze -f`
does) on the box's own disk (`box`: the `kvbox.overlay=` device, mounted at
`/rom/overlay`) and on each named volume (the disk labelled `kv:<name>`); a
disk that is not mounted is skipped. It answers the mount points it froze.
Programs keep running; only their writes wait. `thaw` lets them go on and
answers what it thawed. If no `thaw` comes within `thawAfterSec` (default 30,
at most 120), the agent thaws by itself, so a host that died in between never
leaves the box's writes blocked. One freeze at a time.

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

`postgres/` (kvbox issues #87, #173) is `FROM kvbox-base:local` plus
`postgresql-18` from the PostgreSQL project's apt repository (PGDG), so minor
releases arrive with each image release, and `postgresql-18-pgvector` from the
same repository. pgvector is installed, not enabled. It does not ship as a
trusted extension, and the database's role is never a superuser, so the build
appends `trusted = true` to `vector.control`: the role runs `CREATE EXTENSION
vector` itself, and the install script runs as the bootstrap superuser like any
trusted extension's. The build fails if a pgvector release starts saying
anything about trust itself, so the override is reread rather than stacked. A cluster is created at build time with
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
  "connect": "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${BOX}.kvbox:5432/${POSTGRES_DB}",
  "scripts": {
    "status": "/usr/local/sbin/kvbox-postgres-status",
    "password": "/usr/local/sbin/kvbox-postgres-password"
  }
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
- `scripts` (optional, kvbox #173): named scripts in the box the host may run
  through kvbox-agent's `script` (base v0.14.0 and later); the host knows only
  the names, each image decides what they do.

So the box always receives `POSTGRES_USER`, `POSTGRES_DB` and
`POSTGRES_PASSWORD` through kvbox-agent's `env`. `kvbox-postgres-init.service`
runs at every boot until `/var/lib/kvbox/postgres-init.done` exists: it waits
for `/run/kvbox/env-ready` (up to 5 minutes), reads the three variables from
`/etc/kvbox/env` (parsed, never sourced), creates the role (`LOGIN CREATEDB`)
unless it exists, sets its password, creates the database owned by it unless
it exists, then writes the marker. Without a password it does nothing and
leaves no marker, so a later boot retries. Its log is
`journalctl -u kvbox-postgres-init`.

Before that, with the server stopped, the same script (kvbox #173):

- makes the box's own self-signed TLS certificate (ten years,
  `/etc/postgresql/18/main/kvbox-server.{crt,key}`) and turns `ssl` on with it:
  the certificate the package made at build time would be the same key in every
  box. A client asks for it with `sslmode=require`.
- with `POSTGRES_DATA=/mnt/<volume>/<directory>`, keeps the data on that volume:
  an empty cluster is created there (`initdb`, built beside its final place and
  renamed) unless one exists, and `data_directory` points at it; an existing
  cluster of the same major version is used as it is. The volume must be
  mounted: when it is not, nothing is done and the next boot retries, so a
  volume attached after the box was made (the attach restarts the box) is
  picked up then. `postgresql@.service` starts after `kvbox-volumes.service`.

The role is never a superuser unless it is `postgres` itself; with another
`POSTGRES_USER`, `postgres` has no password and only the local socket.

The two scripts `image.json` names:

- `status` prints `{"ready", "accepting", "version", "connections",
  "dataBytes", "storage": {"usedBytes", "totalBytes"}}`: whether the init has
  finished, whether the server answers, its version, the client sessions open,
  the size of all databases and the filesystem holding the data (the volume
  with `POSTGRES_DATA`).
- `password` reads `{"user", "password"}` and sets that role's password as the
  local superuser (`postgres` itself is refused), printing `{"user"}`.

```
kvbox new mydb --base postgres -e POSTGRES_PASSWORD=x -e POSTGRES_USER=me -e POSTGRES_DB=app
```

## The garage image

`garage/` (kvbox issue #182) is `FROM kvbox-base:local` plus Garage, an
S3-compatible object store: the project's static binary
(`garagehq.deuxfleurs.fr/_releases/v<version>/<arch>-unknown-linux-musl/garage`),
the version and both checksums pinned in the Dockerfile (`GARAGE_VERSION`; the
project publishes no checksums, they are of the files as downloaded). The
server runs as the user `garage` from `garage.service`. It is what kvbox's
Object Storage runs on: one box per account, hidden from the user, whose
buckets and keys the control plane makes through the scripts below.

```json
{
  "autoHibernate": false,
  "scripts": {
    "status": "/usr/local/sbin/kvbox-garage-status",
    "bucket": "/usr/local/sbin/kvbox-garage-bucket",
    "key": "/usr/local/sbin/kvbox-garage-key"
  }
}
```

Nothing listens until the box knows where its data goes: `garage.service` is
skipped while `/etc/garage.toml` is missing. `kvbox-garage-init.service` runs
at every boot. Until `/var/lib/kvbox/garage-init.done` exists it waits for
`/run/kvbox/env-ready`, reads `GARAGE_DATA` and `GARAGE_REGION` from
`/etc/kvbox/env` (parsed, never sourced), then

- requires `GARAGE_DATA=/mnt/<volume>[/<directory>]` on a mounted volume (a
  bare `/mnt/<volume>` becomes `/mnt/<volume>/garage`); when the volume is not
  mounted nothing is done and the next boot retries;
- keeps everything on the volume: `meta/`, `data/` and `rpc_secret`. A box
  whose volume is detached has no `rpc_secret`, so the server refuses to start
  instead of starting empty on the box's own disk;
- writes `/etc/garage.toml` (LMDB, both fsyncs on, `replication_factor = 1`,
  RPC on localhost only, S3 on `[::]:3900`, the web endpoint on `[::]:3902`,
  region `GARAGE_REGION`: a name
  such as `ro-west-1`, `us-east-1` when not sent, fixed from then on since every
  request is signed with it), starts the
  server and makes this node the whole cluster (zone `kvbox`, the volume's
  size as capacity) unless the volume already has a layout.

Once the marker exists it only brings an older box's `/etc/garage.toml` up to
this image (a box moved here by `kvbox vm update` gets the `[s3_web]` section,
and the server restarts) and exits.

There is no TLS and no admin API port: kvbox's edge ends TLS, and the scripts
use `garage json-api`, which goes over the local RPC. Each script takes one
JSON object and prints one (the kvbox-agent `script` contract):

| Script | Input | Output |
|---|---|---|
| `status` | none | `{ready, accepting, version, storage: {usedBytes, totalBytes}, buckets: [{name, objects, bytes, public?}]}`, `public` the host names of a public bucket |
| `bucket` | `{"op": "create", "name"}` | `{"id"}`; a taken name is an error |
| `bucket` | `{"op": "rm", "name"}` | `{"removed", "keys"}`; refuses a bucket that holds objects, removes the keys that open it |
| `bucket` | `{"op": "cors", "name", "origins"}` | `{"origins"}`; these origins may GET, HEAD and PUT and read `ETag` (the web app's uploads), and unfinished uploads are dropped after 2 days (garage v0.3.0+) |
| `bucket` | `{"op": "public", "name", "on": true, "host", "index"?}` | `{"public", "hosts"}`; every object readable without a signature at `http://<host>:3902/<key>`, any origin may GET it, `index` (default `index.html`) for a path ending in `/`, nothing listed; `"on": false` undoes it (garage v0.3.0+) |
| `key` | `{"op": "create", "bucket", "name", "readOnly"}` | `{"id", "secret"}`, the only time the secret leaves the box |
| `key` | `{"op": "rm", "id"}` | `{"removed"}` |

A key opens the one bucket it was made for (read, and write unless
`readOnly`), never with the owner permission. CORS and lifecycle rules are S3
settings only a key with the owner permission may write, so `cors` and `public`
make one for the call and remove it after.

A public bucket is served by Garage's web endpoint, which picks the bucket by
the `Host` header among its names: `public` gives the bucket its host name
(say `assets-alex.kvbox.app`) as a second name. kvbox bucket names never have a
dot, so a name with one is always a host name. Garage has no per-object or
per-prefix permission: public is the whole bucket. Logs: `journalctl -u
kvbox-garage-init` and `journalctl -u garage`.

## The registry image

`registry/` (kvbox issue #234) is `FROM kvbox-base:local` plus zot, an OCI
container registry: the project's static "minimal" build (the registry alone,
without the search, UI and mirroring extensions;
`github.com/project-zot/zot/releases/download/v<version>/zot-linux-<arch>-minimal`),
the version and both checksums pinned in the Dockerfile (`ZOT_VERSION`), plus
`apache2-utils` for `htpasswd`. The server runs as the user `zot` from
`zot.service`. It is what kvbox's container registry runs on: one box per
account, hidden from the user, reached at an HTTPS name through kvbox's edge.

```json
{
  "autoHibernate": false,
  "generate": ["REGISTRY_PASSWORD"],
  "scripts": {
    "status": "/usr/local/sbin/kvbox-registry-status",
    "password": "/usr/local/sbin/kvbox-registry-password"
  }
}
```

Nothing listens until the box has a password: `zot.service` is skipped while
`/etc/zot/config.json` or `/etc/zot/htpasswd` is missing.
`kvbox-registry-init.service` runs at every boot. Until
`/var/lib/kvbox/registry-init.done` exists it waits for `/run/kvbox/env-ready`,
reads `REGISTRY_PASSWORD` and `REGISTRY_DATA` from `/etc/kvbox/env` (parsed,
never sourced), then

- takes `REGISTRY_DATA=/mnt/<volume>[/<directory>]` on a mounted volume (a bare
  `/mnt/<volume>` becomes `/mnt/<volume>/registry`), or `/var/lib/zot` on the
  box's own disk when it is not sent; when the volume is not mounted nothing is
  done and the next boot retries;
- writes `/etc/zot/htpasswd`: the one login, user `kvbox`, the password as a
  bcrypt hash (so at most 72 bytes). It is on the box's own disk, not with the
  images: a volume restored from a backup keeps the password the registry has
  now;
- writes `/etc/zot/config.json` and starts the server: port 5000 on every
  address, plain HTTP (kvbox's edge ends TLS); `readTimeout` and `writeTimeout`
  of one hour, because zot's own 60 seconds are for a whole request and docker
  sends a layer as one request; a layer two repositories share stored once
  (`dedupe`); what no tag names any more removed while the server runs, an hour
  after it was last needed (`gc`, `gcDelay`, `gcInterval`), so deleting a tag
  gives its space back without a restart;
- waits until the server takes the login, then writes the marker.

Each script takes one JSON object and prints one (the kvbox-agent `script`
contract):

| Script | Input | Output |
|---|---|---|
| `status` | none | `{ready, accepting, version, user, storage: {usedBytes, totalBytes}, repositories: [{name, tags}], repositoriesTruncated?}`; the repositories are read from the data directory (at most 1000), so no password is needed |
| `password` | `{"password"}` | `{"user"}`; rewrites `/etc/zot/htpasswd`, which zot watches: the new password works within seconds with no restart, the old one stops. Answers once a login with the new one works, and puts the old file back if it never does |

A client first asks without a login and must get zot's own `401` with its
`WWW-Authenticate: Basic` header: nothing in front of the box may answer in its
place. One upload request may last as long as the layer takes, so whatever is
in front must allow that too (kvbox's edge and hosts give an hour; a Traefik in
front of the edge needs its entry point's `readTimeout` raised to match).
Logs: `journalctl -u kvbox-registry-init` and `journalctl -u zot` (warnings and
errors only).

```
kvbox new cr --base registry
```

## The redis image

`redis/` (kvbox issue #176) is `FROM kvbox-base:local` plus Valkey, the BSD
continuation of Redis: `valkey-server`, `valkey-cli` (also as `redis-cli`) and
`valkey-check-aof` from the Valkey project's binary release for this Ubuntu
(`download.valkey.io/releases/valkey-<version>-noble-<arch>.tar.gz`), the
version and both checksums pinned in the Dockerfile (`VALKEY_VERSION`, Ubuntu
24.04's own package is the old 7.2 line). The server runs as the user `valkey`
from `valkey.service`.

```json
{
  "autoHibernate": false,
  "generate": ["REDIS_PASSWORD"],
  "connect": "redis://default:${REDIS_PASSWORD}@${BOX}.kvbox:6379",
  "scripts": {
    "status": "/usr/local/sbin/kvbox-redis-status",
    "password": "/usr/local/sbin/kvbox-redis-password"
  }
}
```

Nothing listens until the box has its password: `valkey.service` is skipped
while `/etc/valkey/kvbox-auth.conf` is missing. `kvbox-redis-init.service` runs
at every boot until `/var/lib/kvbox/redis-init.done` exists: it waits for
`/run/kvbox/env-ready` (up to 5 minutes), reads `REDIS_PASSWORD` and
`REDIS_DATA` from `/etc/kvbox/env` (parsed, never sourced), then

- makes the box's own self-signed TLS certificate (ten years,
  `/etc/valkey/kvbox-server.{crt,key}`);
- with `REDIS_DATA=/mnt/<volume>/<directory>`, keeps the data on that volume
  (without it, in `/var/lib/valkey` on the box's disk). The volume must be
  mounted: when it is not, nothing is done and the next boot retries, so a
  volume attached after the box was made (the attach restarts the box) is
  picked up then. `valkey.service` starts after `kvbox-volumes.service`;
- writes `/etc/valkey/kvbox.conf` (`dir`, `tls-port 6380`, the certificate)
  and `/etc/valkey/kvbox-auth.conf` (`requirepass`), both included by
  `/etc/valkey/valkey.conf`, starts the server, waits until it answers with
  the password and writes the marker.

Without a password it does nothing and leaves no marker. Its log is
`journalctl -u kvbox-redis-init`; the server's is `journalctl -u valkey`.

What `valkey.conf` settles for every box:

- **Two ports**: plain on 6379 and TLS on 6380, every address; the host
  firewall decides who reaches a box. The only login is the `default` user
  with the password; a TLS client is not asked for a certificate.
- **Persistence**: the append-only file, `appendfsync everysec`, in
  `appendonlydir` under the data directory; no RDB snapshots on a timer.
- **Memory**: `kvbox-redis-run` (the unit's `ExecStart`) gives the server
  `maxmemory` = 75% of the box's `MemTotal`, read at every start; the rest is
  the OS and the pages a fork copies during an AOF rewrite. The policy is
  `noeviction`: a full server refuses writes, it never drops keys.
- `vm.overcommit_memory = 1` (`/etc/sysctl.d/60-kvbox-redis.conf`) and
  transparent huge pages off (`/etc/tmpfiles.d/kvbox-redis.conf`), as Valkey
  asks.

The two scripts `image.json` names:

- `status` prints `{"ready", "accepting", "version", "clients", "memory":
  {"usedBytes", "maxBytes"}, "storage": {"usedBytes", "totalBytes"}}`: whether
  the init has finished, whether the server answers (and has loaded its
  data), its version, the client connections open, what the data takes of
  `maxmemory`, and the filesystem holding the data (the volume with
  `REDIS_DATA`).
- `password` reads `{"password"}`, sets it on the running server (`CONFIG SET
  requirepass`, the password on stdin, never argv) and rewrites
  `kvbox-auth.conf` so the next start has it, printing `{"user": "default"}`.
  A failure leaves both with the old one. Connections already open stay open.

```
kvbox new cache --base redis                       # the password is generated and printed
kvbox new cache --base redis -e REDIS_PASSWORD=x
```

## The k3s image

`k3s/` (kvbox issue #214) is `FROM kvbox-base:local` plus k3s: the one binary
(`/usr/local/bin/k3s`, also as `kubectl` and `crictl`) and k3s's "airgap"
images (coredns, traefik, local-path, metrics-server, klipper, pause) from the
k3s project's GitHub release, the version and four checksums pinned in the
Dockerfile (`K3S_VERSION`). Nothing is downloaded when a box boots. Every box
of a cluster runs this image, its server (the master) and its nodes alike; it
is what kvbox's managed Kubernetes is made of.

```json
{
  "autoHibernate": false,
  "scripts": {
    "status": "/usr/local/sbin/kvbox-k3s-status",
    "kubeconfig": "/usr/local/sbin/kvbox-k3s-kubeconfig",
    "drain": "/usr/local/sbin/kvbox-k3s-drain",
    "rotate": "/usr/local/sbin/kvbox-k3s-rotate"
  }
}
```

Nothing runs until the box knows its part: `k3s.service` is skipped while
`/etc/rancher/k3s/config.yaml` is missing. `kvbox-k3s-init.service` runs at
every boot until `/var/lib/kvbox/k3s-init.done` exists: it waits for
`/run/kvbox/env-ready` (up to 5 minutes), reads the box's variables from
`/etc/kvbox/env` (parsed, never sourced), checks them, writes
`/etc/kvbox/k3s.conf` (role and data directory) and k3s's `config.yaml`, starts
`k3s.service`, waits until it is up (the API answers ready on a server, the
unit is active on an agent) and writes the marker. With a variable missing or
wrong nothing is written and the next boot retries.

| Variable | For | Meaning |
|---|---|---|
| `K3S_ROLE` | both | `server` or `agent` |
| `K3S_TOKEN` | both | an agent: what it joins with. A server: its own token, which no other box should be given, since with it comes the whole cluster (8+ characters of letters, digits and `. _ : ~ + / = @ -`) |
| `K3S_AGENT_TOKEN` | server, optional | what agents join with (k3s's `agent-token`, v0.1.5): a token that joins a node and nothing more. Without it agents join with the server's own token |
| `K3S_URL` | agent | the server's address, `https://<name or address>:6443` |
| `K3S_TLS_SAN` | server, optional | more names or addresses for the API's certificate, comma separated: the public address `kubectl` uses from outside |
| `K3S_DATA` | server, optional | a directory on a volume (`/mnt/<volume>/…`, a bare `/mnt/<volume>` becomes `/mnt/<volume>/k3s`) for the cluster's state; without it the state is on the box's own disk |
| `K3S_NODE_LABELS` | agent, optional | labels for the node (v0.1.8, kvbox #235), comma separated `key=value`: kvbox sends `kvbox.sh/pool=<the node's pool>` |

- The node's name is the box's name.
- A server gets the taint `CriticalAddonsOnly=true:NoExecute`: only the
  system's own pods run on it, what the owner deploys lands on the nodes. The
  init adds it once k3s's own install jobs are done (up to 5 minutes), not in
  k3s's configuration: those jobs do not tolerate it, so a server tainted from
  its first start would have no Traefik until a node joined. Traefik tolerates
  the taint and stays on the server.
- `kvbox-k3s-mounts` runs before every start of k3s. A box's `/` is an
  overlayfs, and containerd's overlayfs snapshotter refuses to keep its layers
  on one, so `/var/lib/rancher` and `/var/lib/kubelet` are directories of the
  box's own disk (`/rom/overlay/…`), as the base image does for
  `/var/lib/docker`. The baked images (`/usr/local/share/kvbox/k3s-images`) are
  mounted where k3s looks for them. With `K3S_DATA`, that directory is mounted
  on `/var/lib/rancher/k3s/server`; when its volume is not mounted the start
  fails and is tried again, so k3s never begins a new, empty cluster beside its
  data.
- On a server `kvbox-k3s-mounts` also writes
  `server/manifests/kvbox-traefik.yaml` (a `HelmChartConfig`): Traefik trusts
  the `X-Forwarded-*` headers on its port 80, so an app behind an Ingress sees
  `https` and the visitor's address when kvbox's edge ends TLS for the cluster
  (kvbox #219). That port is reached only by the box's host and the cluster's
  own boxes and pods.
- On a server it also writes `server/manifests/kvbox-dns.yaml` (v0.1.6, kvbox
  #243): the ConfigMap `coredns-custom` with one server block, `kvbox:53`, that
  forwards every name under `.kvbox` to the box's host (the first nameserver of
  the box's `/etc/resolv.conf`) and nowhere else. Without it CoreDNS spreads
  such a lookup over the box's three resolvers, two of them public, and a pod
  cannot resolve a linked database's `<name>.<slug>.kvbox`. k3s writes that
  ConfigMap at each start, so a key added to it by hand does not last.

- Pods send packets of at most 1290 bytes (v0.1.7, kvbox #226). A cluster's
  nodes may be on several hosts, and the road between two hosts is a WireGuard
  tunnel with an MTU of 1340; flannel's VXLAN wraps each packet in 50 bytes
  more and would size itself by the box's own interface (pods at 1450), so a
  full packet would be lost on the way to another host. The init writes
  `/etc/rancher/k3s/flannel.json`, what k3s writes for flannel itself plus
  `"MTU": 1340` in the VXLAN backend (the wrapped packet's size: flannel gives
  the pods 50 less), and names it as `flannel-conf` in `config.yaml`, on the
  server and on every agent, whether or not the cluster ever leaves one host.
  The number is `NODE_MTU` in `kvbox-k3s-init`; the file also names k3s's
  default pod network, `10.42.0.0/16`. A box set up by an earlier version
  keeps 1450: the init runs once per box.
- An agent takes its node's labels from `K3S_NODE_LABELS` (v0.1.8, kvbox
  #235): each `key=value` becomes a `node-label` entry of `config.yaml`, so a
  workload picks a pool with `nodeSelector: {kvbox.sh/pool: <pool>}`. Each is
  checked as Kubernetes would (a key is `[<prefix>/]<name>`, name and value at
  most 63 of letters, digits and `- _ .` that begin and end with a letter or
  digit, the value may be empty); one that is not a label, a key under
  `kubernetes.io` or `k8s.io` (the kubelet refuses to start with most of
  those) and a key named twice are said in the log and left out, and k3s
  starts all the same: a bad label never keeps a node out of its cluster. k3s
  gives a node its labels only when it first registers, which is enough for a
  pool's name: a node is of one pool for life. A server ignores the variable,
  and so does an image from before v0.1.8: its nodes have no label.
- A server also listens on port 6445 (`kvbox-k3s-api.socket`, enabled by the
  init on a server only, v0.1.5): the Kubernetes API alone, passed byte for
  byte to the API server's own port (6444, localhost only), for publishing
  outside. Port 6443 is the API and k3s's own door at once (a token joins a
  node there, the server's token replaces the cluster's certificate
  authorities) and is meant for the cluster's own boxes. A kubeconfig works on
  either: the certificate is signed by the same authority and carries the
  `K3S_TLS_SAN` names.

The scripts take one JSON object and answer one; `kubeconfig` and `drain` are
for the server.

| Script | Input | Output |
|---|---|---|
| `status` | none | `{"ready", "role", "version", "accepting", "podMtu", "certificatesEndAt", "ingress", "nodes"}`; `podMtu` (v0.1.7): the largest packet this box's pods send, as flannel set it up at this boot, 1290 on a box set up by v0.1.7 or later and 1450 on one from before, absent until flannel is up; `certificatesEndAt` on a server (v0.1.5): when the first of k3s's own certificates ends (they last a year and are renewed only when k3s starts within 120 days of that); `ingress` (Traefik has a pod available) and `nodes` on a server whose API answers: `{"name", "ready", "schedulable", "roles", "version", "address", "bootId", "volumes", "claims"}` each, `volumes` the bound persistent volumes kept on that node's disk and `claims` their claims as `namespace/name` (v0.1.2), `bootId` the kubelet's boot id, new at every boot of the node (v0.1.5); `nodes` is absent when the nodes or their volumes could not be listed (v0.1.3) |
| `kubeconfig` | `{"address", "port", "name"?}` | `{"kubeconfig"}`: the admin kubeconfig with the server set to that address and port; `name` renames the cluster, user and context (k3s calls them `default`) |
| `drain` | `{"op": "start", "node"}` | `{"node", "state"}`; cordons the node, moves its pods away and deletes the node object, in the background (a drain outlasts a script): `draining`, or `done` for a node the cluster does not know |
| `drain` | `{"op": "state", "node"}` | `{"node", "state", "error"?}`: `draining`, `done` (the node object is gone), `failed` with `error` (start again), `idle` |
| `drain` | `{"op": "delete", "node"}` | `{"node", "state": "done"}`; the node out of the cluster at once, nothing waited for (v0.1.2): a drain of it is stopped and the node object deleted, for a node whose box goes whatever its pods say |
| `drain` | `{"op": "stop", "node"}` | `{"node", "state"}`: a drain given up (v0.1.3): its unit stopped before it deletes the node, which stays cordoned (`idle`, or `done` when the cluster no longer knows it) |
| `rotate` | server: `{"token", "agentToken"}` | `{"rotated": true, "role": "server"}` (v0.1.5): the server's token replaced (`k3s token rotate`), both tokens written to `config.yaml`, new certificate authorities stored (`k3s certificate rotate-ca --force`). Nothing takes effect before k3s starts again: the caller restarts the box. Every certificate from before, a saved kubeconfig's included, then stops being believed. Service account tokens are not touched. Safe to ask again after a failure. From v0.1.9 the authorities are stored with the token from before (the running k3s asks for the old one until it starts again; kept as `server/token.before-rotate` meanwhile): before that the second step was always refused, and rotate never worked. From v0.1.10 a marker (`/var/lib/kvbox/k3s-rotated`) has `kvbox-k3s-after-rotate.service` start kube-system's deployments again once at the server's next start, when `kube-root-ca.crt` carries the new authority: before that CoreDNS kept the old one and no name inside the cluster resolved after a rotate. From v0.1.11 the agents' new token is written into `server/cred/passwd` before the server's token is replaced, so k3s's copy of that file in its datastore holds it: before that the first start after a rotate changed the file alone and the next start refused to run (`passwd newer than datastore`), so a rotated cluster lost its server at its next restart |
| `rotate` | agent: `{"token"}` | `{"rotated": true, "role": "agent"}`: the token it joins with at its next start |

When something is wrong, the box's journal says what: `journalctl -u
kvbox-k3s-init` and `journalctl -u k3s`. Needs kernel `v6.1.190-3` or later.

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
systemd service with `svc.sh` unless `.service` exists, adds a drop-in with
`Restart=always` (a runner killed by the OOM killer comes back by itself),
starts it and writes the marker. The runner service is enabled, so it is back
after every boot. `kvbox-docker-prune.timer` runs `docker system prune -af
--filter until=24h` once a day so CI's images and build cache don't fill the disk.
Without a URL or token it does nothing and leaves no marker. Its log is
`journalctl -u kvbox-gh-runner-init`.

```
kvbox new ci --base gh-runner -e GITHUB_URL=https://github.com/<owner>/<repo> -e GITHUB_RUNNER_TOKEN=<token>
```

## The android image

`android/` is `FROM kvbox-base:local` plus what testing an Android app with
Appium takes: `openjdk-17-jdk-headless`, `maven`, the Android SDK in
`/opt/android-sdk` (command-line tools, platform-tools for `adb`, build-tools
for `apksigner` and `aapt2`) and Appium with the UiAutomator2 driver
(`APPIUM_HOME=/opt/appium`). `/etc/profile.d/kvbox-android.sh` puts them on
every login shell's PATH.

Android is not emulated: `kvbox-android.service` runs a
[Redroid](https://github.com/remote-android/redroid-doc) container (Android's
own processes on the box's kernel, `redroid/redroid:14.0.0-latest` by default,
pulled at the first boot), publishes its adb on `127.0.0.1:5600` (not 5555: adb also scans that
port as an emulator, so it would list Android twice), connects the
`kvbox` user's adb to it and waits until Android has booted. Android's `/data`
(installed apps and their files) is `/var/lib/redroid`, kept across restarts.
The box's variables `REDROID_IMAGE` and `REDROID_ARGS` (extra boot properties,
e.g. `androidboot.redroid_width=1080`) change what runs at the next start.
There is no GPU: Android draws in software (`redroid_gpu_mode=guest`).
`kvbox-appium.service` then runs Appium as `kvbox` on port 4723; it has no
login, so publish the port only if tests run outside the box.

Android talks through binder, which the usual kernel leaves out. The image's
`image.json` says `"kernel": "android"`, so kvbox boots its boxes with the
android kernel (`kernel-android/`: `kernel/kvbox.config` plus
`kernel/android.config`) and every other box keeps the kernel without binder.
On a box whose kernel has no binder, `kvbox-android.service` fails and says so.

```
kvbox new phone --base android --size l
kvbox exec phone -- adb devices              # localhost:5600  device
kvbox exec phone -- 'adb install app.apk'    # then point Appium at udid localhost:5600
```

Give the box room: the Redroid image and Android's data live on its disk.

## Build

Needs Docker; no root and no loop mount on the host.

```
base/build.sh                 # -> base/out/rootfs.ext4 (8 GiB sparse, ~1.9 GB used), .sha256, .zst
ROOTFS_SIZE=16G base/build.sh # larger disk
postgres/build.sh             # -> postgres/out/rootfs.ext4; builds base's Dockerfile first (kvbox-base:local)
redis/build.sh                # -> redis/out/rootfs.ext4; same
gh-runner/build.sh            # -> gh-runner/out/rootfs.ext4; same
k3s/build.sh                  # -> k3s/out/rootfs.ext4; same
registry/build.sh             # -> registry/out/rootfs.ext4; same
android/build.sh              # -> android/out/rootfs.ext4 (10 GiB sparse); same
kernel/build.sh               # -> kernel/out/vmlinux (several minutes the first time, cached after)
kernel-android/build.sh       # -> kernel-android/out/vmlinux: the same plus kernel/android.config
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
./release.sh redis v0.1.0       # builds, then publishes release redis-v0.1.0 (rootfs-redis-<arch>.ext4.zst)
./release.sh k3s v0.1.0         # builds, then publishes release k3s-v0.1.0 (rootfs-k3s-<arch>.ext4.zst)
./release.sh registry v0.1.0    # builds, then publishes release registry-v0.1.0 (rootfs-registry-<arch>.ext4.zst)
./release.sh kernel v6.1.190-1  # builds, then publishes release kernel-v6.1.190-1
./release.sh android v0.1.0     # builds, then publishes release android-v0.1.0 (rootfs-android-<arch>.ext4.zst)
./release.sh kernel-android v6.1.190-1  # builds, then publishes release kernel-android-v6.1.190-1 (vmlinux-android-<arch>)
```

Every release also rewrites `images.json` on the fixed release `index`: the latest version of each
image and of the kernel, made from the list of releases (`./release.sh index` rewrites it alone).
kvbox's `install-server.sh` installs what it lists, so a release is all it takes for hosts to get an
image at their next install or update; `ROOTFS_VERSION`, `IMAGES` and `KERNEL_VERSION` pin a host by
hand. A pre-release is left out of the list. An image whose newest version needs a newer kvbox-server
names it in `<image>/min-server` (one line, e.g. `0.5.48`): hosts are not given that image until that
kvbox-server is on npm.

## License

MIT
