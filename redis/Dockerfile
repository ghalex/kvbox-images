# kvbox redis image (kvbox #176): the base image plus Valkey (BSD, speaks the Redis protocol) from the
# Valkey project's own binary release for this Ubuntu (download.valkey.io, checksum pinned below).
# Built by redis/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# Nothing listens until the box owner's variables arrive: kvbox-redis-init.service takes the password
# (REDIS_PASSWORD) and optionally a data directory on a volume (REDIS_DATA), makes the box's own TLS
# certificate and only then starts valkey.service: plain on 6379, TLS on 6380, AOF on.
FROM kvbox-base:local

ENV DEBIAN_FRONTEND=noninteractive
# A new version: change it and both checksums (https://download.valkey.io/releases/<file>.sha256).
ARG VALKEY_VERSION=9.1.3
ARG VALKEY_SHA256_X86_64=26416df8a5b075ffb7d549e9a6445db9ec16e36d2259d8ea6e010dca35d53a54
ARG VALKEY_SHA256_ARM64=bf77cf1adf9dc2b1e1f42a01b611b5b8d00c5c158a200ab9ad1f8837d84d59da
RUN . /etc/os-release \
    && case "$(uname -m)" in \
         x86_64)  arch=x86_64; sum="$VALKEY_SHA256_X86_64" ;; \
         aarch64) arch=arm64;  sum="$VALKEY_SHA256_ARM64" ;; \
         *) echo "no Valkey build for $(uname -m)" >&2; exit 1 ;; \
       esac \
    && file="valkey-$VALKEY_VERSION-$VERSION_CODENAME-$arch.tar.gz" \
    && curl -fsSL -o "/tmp/$file" "https://download.valkey.io/releases/$file" \
    && echo "$sum  /tmp/$file" | sha256sum -c - \
    && tar -xzf "/tmp/$file" -C /tmp \
    && install -m 0755 "/tmp/${file%.tar.gz}/bin/valkey-server" "/tmp/${file%.tar.gz}/bin/valkey-cli" "/tmp/${file%.tar.gz}/bin/valkey-check-aof" /usr/local/bin/ \
    && install -D -m 0644 "/tmp/${file%.tar.gz}/share/LICENSE" /usr/share/doc/valkey/LICENSE \
    && ln -s valkey-cli /usr/local/bin/redis-cli \
    && rm -rf "/tmp/$file" "/tmp/${file%.tar.gz}" \
    && useradd --system --home-dir /var/lib/valkey --shell /usr/sbin/nologin valkey \
    && install -d -m 0750 -o valkey -g valkey /var/lib/valkey \
    # The server must be this version, with TLS and systemd's notify built in (kvbox-redis-init and valkey.service rely on both).
    && valkey-server --version | grep -q "v=$VALKEY_VERSION " \
    && ldd /usr/local/bin/valkey-server | grep -q libssl \
    && ldd /usr/local/bin/valkey-server | grep -q libsystemd

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-redis-init /usr/local/sbin/kvbox-redis-run /usr/local/sbin/kvbox-redis-status /usr/local/sbin/kvbox-redis-password \
    && chmod 0644 /etc/kvbox/image.json /etc/valkey/valkey.conf /etc/systemd/system/valkey.service /etc/systemd/system/kvbox-redis-init.service \
       /etc/sysctl.d/60-kvbox-redis.conf /etc/tmpfiles.d/kvbox-redis.conf \
    && chown root:valkey /etc/valkey && chmod 0750 /etc/valkey \
    && systemctl enable valkey.service kvbox-redis-init.service
