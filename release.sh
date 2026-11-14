#!/usr/bin/env bash
# Build an image and publish it as a GitHub release of this repo.
#
#   ./release.sh base v0.1.0        # -> release "base-v0.1.0" with rootfs-base-<arch>.ext4.zst + .sha256
#   ./release.sh postgres v0.1.0    # -> release "postgres-v0.1.0" with rootfs-postgres-<arch>.ext4.zst + .sha256
#   ./release.sh redis v0.1.0       # -> release "redis-v0.1.0" with rootfs-redis-<arch>.ext4.zst + .sha256
#   ./release.sh kernel v6.1.190-1  # -> release "kernel-v6.1.190-1" with vmlinux-<arch> + .sha256
#
#   ./release.sh index              # -> only rewrite images.json (below), nothing is built
#
# <image>/build.sh builds and leaves the assets, named as install-server.sh expects them, in
# <image>/out/release/; this script uploads that directory.
#
# Every release also rewrites images.json on the fixed release "index": the latest version of each
# image and of the kernel. kvbox's install-server.sh installs what it lists and the control plane shows
# it to the admin, so a release here is all it takes for hosts to get the image at their next update;
# no version is written in the kvbox repo. It is made from the list of releases each time (drafts and
# pre-releases are left out: publish one as a pre-release to keep it from hosts). An image whose newest
# version needs a newer kvbox-server says so in <image>/min-server (one line, e.g. 0.5.48): a host is
# not given that image until that kvbox-server is on npm.
#
#   {"updatedAt": "...", "images": {"base": {"version": "v0.14.0", "minServer": "0.5.48"}, "kernel": {...}, ...}}
#
# Needs: docker, zstd, gh (logged in with push access to this repo).
set -euo pipefail

image="${1:?usage: release.sh <image> <version> | release.sh index}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo=ghalex/kvbox-images
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }

# publish_index [tag just released]: images.json from the releases there are, onto the release "index".
publish_index() {
  local tags dir name latest min entries="" tmp
  tags="$(gh release list --repo "$repo" --limit 1000 --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName')"
  [[ -z "${1:-}" ]] || tags+=$'\n'"$1"
  for dir in "$here"/*/; do
    name="$(basename "$dir")"
    [[ -f "$dir/build.sh" ]] || continue
    latest="$(grep -E "^${name}-v[0-9][0-9A-Za-z.-]*$" <<< "$tags" | sed "s/^${name}-//" | sort -uV | tail -1 || true)"
    [[ -n "$latest" ]] || continue
    min=""
    if [[ -f "$dir/min-server" ]]; then
      min="$(tr -d '[:space:]' < "$dir/min-server")"
      [[ "$min" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "$name/min-server: expected a version like 0.5.48, got \"$min\"" >&2; exit 1; }
    fi
    entries+="${entries:+,$'\n'}    \"$name\": { \"version\": \"$latest\"${min:+, \"minServer\": \"$min\"} }"
  done
  [[ -n "$entries" ]] || { echo "no released image found in $repo; images.json not written" >&2; exit 1; }
  tmp="$(mktemp -d)"
  printf '{\n  "updatedAt": "%s",\n  "images": {\n%s\n  }\n}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$entries" > "$tmp/images.json"
  if gh release view index --repo "$repo" >/dev/null 2>&1; then
    gh release upload index "$tmp/images.json" --clobber --repo "$repo"
  else
    gh release create index "$tmp/images.json" --repo "$repo" --latest=false --title "index" \
      --notes "images.json: the latest version of every image and of the kernel, rewritten by release.sh at each release. kvbox's install-server.sh and control plane read it."
  fi
  echo "published images.json:"
  cat "$tmp/images.json"
  rm -rf "$tmp"
}

if [[ "$image" == index ]]; then
  publish_index
  exit 0
fi

version="${2:?usage: release.sh <image> <version>}"
arch="$(uname -m)"
tag="${image}-${version}"

[[ -d "$here/$image" ]] || { echo "no such image: $image" >&2; exit 1; }
[[ "$version" =~ ^v[0-9][0-9A-Za-z.-]*$ ]] || { echo "version must look like v0.1.0, got $version" >&2; exit 1; }

"$here/$image/build.sh"

rel="$here/$image/out/release"
[[ -d "$rel" ]] && [[ -n "$(ls -A "$rel")" ]] || { echo "$image/build.sh left no release assets in $rel" >&2; exit 1; }
assets=("$rel"/*)

case "$image" in
  base)   what="Base guest image $version ($arch): Ubuntu 24.04 with Python 3, Node.js 22, Docker, nginx (for kvbox deploy), Claude Code and kvbox-agent (vsock control channel for snapshot restores)."
          how="ROOTFS_VERSION=$version ./install-server.sh" ;;
  postgres) what="Postgres guest image $version ($arch): the base image plus PostgreSQL $(docker run --rm kvbox-postgres:local ls /usr/lib/postgresql) (PGDG), listening on the box's IP with its own TLS certificate; role, database and password from the box's POSTGRES_USER / POSTGRES_DB / POSTGRES_PASSWORD, data on a volume with POSTGRES_DATA (kvbox #87, #173)."
          how="kvbox new mydb --base postgres -e POSTGRES_USER=me -e POSTGRES_DB=app" ;;
  redis)  what="Redis guest image $version ($arch): the base image plus Valkey $(docker run --rm kvbox-redis:local valkey-server --version | sed -n 's/.* v=\([^ ]*\) .*/\1/p') (the Valkey project's own build, speaks the Redis protocol), plain on 6379 and TLS on 6380 with its own certificate, AOF persistence; password from the box's REDIS_PASSWORD, data on a volume with REDIS_DATA (kvbox #176)."
          how="kvbox new cache --base redis" ;;
  kernel) what="Guest kernel $version ($arch): Linux $(cat "$here/kernel/out/vmlinux.version") with Firecracker's CI config plus kernel/kvbox.config (netfilter for Docker, nf_tables, FUSE)."
          how="KERNEL_VERSION=${version#v} ./install-server.sh" ;;
  *)      what="$image $version ($arch)."; how="./install-server.sh" ;;
esac
# shellcheck disable=SC2016  # the backticks are markdown, not command substitution
notes="$(printf '%s\n\nInstall with kvbox: `install-server.sh` downloads the asset, verifies the checksum and puts it in `~/.kvbox/assets`.\n\n```\n%s\n```' "$what" "$how")"

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$tag" "${assets[@]}" --clobber --repo "$repo"
else
  gh release create "$tag" "${assets[@]}" --repo "$repo" --title "$tag" --notes "$notes"
fi
echo "published $tag: $(basename -a "${assets[@]}" | tr '\n' ' ')"
publish_index "$tag"
