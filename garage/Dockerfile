# kvbox garage image (kvbox #182): the base image plus Garage (AGPL, speaks the S3 protocol) from the
# Garage project's own static binary (garagehq.deuxfleurs.fr, checksum pinned below). It is what
# kvbox's Object Storage runs on: one box per account, its data on a volume.
# Built by garage/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# Nothing listens until the box knows where its data goes: kvbox-garage-init.service takes GARAGE_DATA
# (a directory on a volume), writes /etc/garage.toml, starts garage.service (S3 on 3900, plain HTTP:
# kvbox's edge ends TLS) and makes this one node the whole cluster.
FROM kvbox-base:local

ENV DEBIAN_FRONTEND=noninteractive
# A new version: change it and both checksums (the project publishes none: sha256sum of the two files
# at https://garagehq.deuxfleurs.fr/_releases/<version>/<arch>-unknown-linux-musl/garage).
ARG GARAGE_VERSION=2.5.0
ARG GARAGE_SHA256_X86_64=2ff667286217cd73ebcb1c03af993822365000441dfe31a80cb64c5189a9dea8
ARG GARAGE_SHA256_AARCH64=69b6040cef428b993500c17dd0d0c1240acf2f3f667b9b05ceba4b9660db4e8c
RUN case "$(uname -m)" in \
         x86_64)  arch=x86_64;  sum="$GARAGE_SHA256_X86_64" ;; \
         aarch64) arch=aarch64; sum="$GARAGE_SHA256_AARCH64" ;; \
         *) echo "no Garage build for $(uname -m)" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/garage "https://garagehq.deuxfleurs.fr/_releases/v$GARAGE_VERSION/$arch-unknown-linux-musl/garage" \
    && echo "$sum  /tmp/garage" | sha256sum -c - \
    && install -m 0755 /tmp/garage /usr/local/bin/garage \
    && rm -f /tmp/garage \
    && useradd --system --home-dir /var/lib/garage --shell /usr/sbin/nologin garage \
    # The server must be this version (the scripts rely on `garage json-api`, Garage 2.0+).
    && garage --version | grep -q "v$GARAGE_VERSION"

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-garage-init /usr/local/sbin/kvbox-garage-status /usr/local/sbin/kvbox-garage-bucket /usr/local/sbin/kvbox-garage-key \
    && chmod 0644 /etc/kvbox/image.json /etc/systemd/system/garage.service /etc/systemd/system/kvbox-garage-init.service /usr/local/lib/kvbox/garage_api.py \
    && systemctl enable garage.service kvbox-garage-init.service
