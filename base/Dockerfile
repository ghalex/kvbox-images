# kvbox base image: Ubuntu 24.04 with systemd, sshd and a `kvbox` user.
# Built by images/base/build.sh into an ext4 file; never run as a container.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv udev dbus \
      openssh-server sudo \
      ca-certificates curl git \
      iproute2 iputils-ping \
      e2fsprogs \
      less nano \
    && rm -rf /var/lib/apt/lists/*

# kvbox user: passwordless sudo, key-only SSH (the key arrives on the kernel cmdline, see kvbox-init).
# Drop the stock `ubuntu` user so kvbox is uid 1000.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash -G sudo kvbox \
    && mkdir -p /home/kvbox/.ssh && chmod 700 /home/kvbox/.ssh && chown -R kvbox:kvbox /home/kvbox/.ssh

COPY rootfs/ /
RUN chmod 0440 /etc/sudoers.d/kvbox \
    && chmod 0755 /usr/local/sbin/kvbox-init \
    # Host keys are generated per box on first boot, never shared across boxes.
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
    # Generated on first boot too.
    && : > /etc/machine-id \
    # Clients forward LANG/LC_* over SSH and the image only has C.UTF-8: don't accept them,
    # and give the guest a sane default locale (kvbox issue #24).
    && sed -i 's/^AcceptEnv LANG LC_\*/#&/' /etc/ssh/sshd_config \
    && printf 'LANG=C.UTF-8\n' > /etc/default/locale \
    && systemctl enable ssh.service kvbox-init.service \
    # Mask, don't disable: presets re-enable disabled units on first boot (seen in spike #4).
    && systemctl mask systemd-resolved.service systemd-timesyncd.service \
         apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer \
         e2scrub_all.timer e2scrub_reap.service motd-news.timer
