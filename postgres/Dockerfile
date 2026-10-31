# kvbox postgres image (kvbox #87): the base image plus Ubuntu's PostgreSQL, listening on the box's IP.
# Built by postgres/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# The cluster is created at build time; the role, database and password the box owner asked for
# (POSTGRES_USER / POSTGRES_DB / POSTGRES_PASSWORD, sent by the host through kvbox-agent's "env")
# are applied once, at the first boot that has them, by kvbox-postgres-init.service.
FROM kvbox-base:local

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends postgresql \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc/postgresql* /usr/share/postgresql/*/man \
    && ver="$(ls /usr/lib/postgresql)" && test -d "/var/lib/postgresql/$ver/main" \
    && conf="/etc/postgresql/$ver/main" \
    # Every address: the host firewall decides who reaches a box (isolated unless linked).
    && sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '*'/" "$conf/postgresql.conf" \
    && grep -q "^listen_addresses = '\*'" "$conf/postgresql.conf" \
    && printf '\n# kvbox: password logins from anywhere, the host firewall decides who reaches the box\nhost    all             all             0.0.0.0/0               scram-sha-256\nhost    all             all             ::/0                    scram-sha-256\n' >> "$conf/pg_hba.conf"

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-postgres-init \
    && chmod 0644 /etc/kvbox/image.json \
    && systemctl enable postgresql.service kvbox-postgres-init.service
