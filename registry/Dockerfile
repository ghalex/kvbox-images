# kvbox registry image (kvbox #234): the base image plus zot (Apache 2.0, an OCI registry: `docker push`
# and `docker pull`) from the zot project's own static binary (github.com/project-zot/zot, checksum
# pinned below). It is what kvbox's container registry runs on: one box per account, the images on a volume.
# Built by registry/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# Nothing listens until the box has a password: kvbox-registry-init.service takes REGISTRY_PASSWORD and
# REGISTRY_DATA (a directory on a volume), writes /etc/zot/htpasswd and /etc/zot/config.json and starts
# zot.service (port 5000, plain HTTP: kvbox's edge ends TLS).
FROM kvbox-base:local

ENV DEBIAN_FRONTEND=noninteractive
# The "minimal" build: the registry alone, without the search, UI and mirroring extensions.
# A new version: change it and both checksums (sha256sum of zot-linux-<arch>-minimal from the release).
ARG ZOT_VERSION=2.1.23
ARG ZOT_SHA256_AMD64=8a6e77686bc0e7751766c49828cff6c66b115c854d350c9d936b855463f6c973
ARG ZOT_SHA256_ARM64=931d687899cc4b1fcad4c026d2792df6132e6de1b2f329aa730dccee14ec0395
# apache2-utils is `htpasswd`, which makes the bcrypt line zot checks a password against.
RUN case "$(uname -m)" in \
         x86_64)  arch=amd64; sum="$ZOT_SHA256_AMD64" ;; \
         aarch64) arch=arm64; sum="$ZOT_SHA256_ARM64" ;; \
         *) echo "no zot build for $(uname -m)" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/zot "https://github.com/project-zot/zot/releases/download/v$ZOT_VERSION/zot-linux-$arch-minimal" \
    && echo "$sum  /tmp/zot" | sha256sum -c - \
    && install -m 0755 /tmp/zot /usr/local/bin/zot \
    && rm -f /tmp/zot \
    && apt-get update \
    && apt-get install -y --no-install-recommends apache2-utils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --home-dir /var/lib/zot --shell /usr/sbin/nologin zot \
    && install -d -m 0750 -o root -g zot /etc/zot \
    && zot --version 2>&1 | grep -q "v$ZOT_VERSION"

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-registry-init /usr/local/sbin/kvbox-registry-status /usr/local/sbin/kvbox-registry-tags /usr/local/sbin/kvbox-registry-password \
    && chmod 0644 /etc/kvbox/image.json /etc/systemd/system/zot.service /etc/systemd/system/kvbox-registry-init.service \
    && systemctl enable zot.service kvbox-registry-init.service
