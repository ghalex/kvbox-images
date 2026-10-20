# zbox base image: Ubuntu 24.04 with systemd, sshd and a `zbox` user.
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

# zbox user: passwordless sudo, key-only SSH (the key arrives on the kernel cmdline, see zbox-init).
# Drop the stock `ubuntu` user so zbox is uid 1000.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash -G sudo zbox \
    && mkdir -p /home/zbox/.ssh && chmod 700 /home/zbox/.ssh && chown -R zbox:zbox /home/zbox/.ssh

COPY rootfs/ /
RUN chmod 0440 /etc/sudoers.d/zbox \
    && chmod 0755 /usr/local/sbin/zbox-init \
    # Host keys are generated per box on first boot, never shared across boxes.
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
    # Generated on first boot too.
    && : > /etc/machine-id \
    && systemctl enable ssh.service zbox-init.service \
    && systemctl disable systemd-resolved.service systemd-timesyncd.service apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer 2>/dev/null || true \
    && systemctl mask systemd-resolved.service
