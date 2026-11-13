# kvbox postgres image (kvbox #87, #173): the base image plus PostgreSQL 18 from the PostgreSQL
# project's own apt repository (PGDG), listening on the box's IP.
# Built by postgres/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# A cluster is created at build time; the role, database and password the box owner asked for
# (POSTGRES_USER / POSTGRES_DB / POSTGRES_PASSWORD, sent by the host through kvbox-agent's "env")
# are applied once, at the first boot that has them, by kvbox-postgres-init.service. With
# POSTGRES_DATA (a directory on a volume) the data lives there instead of on the box's disk.
FROM kvbox-base:local

ENV DEBIAN_FRONTEND=noninteractive
ARG PG_MAJOR=18
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-common \
    && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
    && apt-get install -y --no-install-recommends "postgresql-$PG_MAJOR" \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc/postgresql* /usr/share/postgresql/*/man \
    && test "$(ls /usr/lib/postgresql)" = "$PG_MAJOR" && test -d "/var/lib/postgresql/$PG_MAJOR/main" \
    && conf="/etc/postgresql/$PG_MAJOR/main" \
    # Every address: the host firewall decides who reaches a box (isolated unless linked).
    && sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '*'/" "$conf/postgresql.conf" \
    && grep -q "^listen_addresses = '\*'" "$conf/postgresql.conf" \
    # kvbox-postgres-init rewrites the first and writes into the second: fail the build if either moved.
    && grep -q "^data_directory = " "$conf/postgresql.conf" \
    && grep -q "^include_dir = 'conf.d'" "$conf/postgresql.conf" \
    && printf '\n# kvbox: password logins from anywhere, the host firewall decides who reaches the box\nhost    all             all             0.0.0.0/0               scram-sha-256\nhost    all             all             ::/0                    scram-sha-256\n' >> "$conf/pg_hba.conf"

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-postgres-init /usr/local/sbin/kvbox-postgres-status /usr/local/sbin/kvbox-postgres-password \
    && chmod 0644 /etc/kvbox/image.json /etc/systemd/system/postgresql@.service.d/kvbox.conf \
    && systemctl enable postgresql.service kvbox-postgres-init.service
