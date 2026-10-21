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
      gnupg \
      python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS (node + npm) from NodeSource, Docker Engine from Docker's own repository:
# Ubuntu's apt ships old versions of both.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      nodejs \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    # A box is disposable: let `pip install` work without a venv (Ubuntu's PEP 668 guard off).
    && printf '[global]\nbreak-system-packages = true\n' > /etc/pip.conf

# kvbox user: passwordless sudo, key-only SSH (the key arrives on the kernel cmdline, see kvbox-init).
# Drop the stock `ubuntu` user so kvbox is uid 1000.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash -G sudo,docker kvbox \
    && mkdir -p /home/kvbox/.ssh && chmod 700 /home/kvbox/.ssh && chown -R kvbox:kvbox /home/kvbox/.ssh

# Claude Code CLI, installed as the kvbox user with Anthropic's native installer: lands in
# ~/.local/bin (on PATH via Ubuntu's default ~/.profile) and updates itself from there.
USER kvbox
RUN HOME=/home/kvbox bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    && test -x /home/kvbox/.local/bin/claude
USER root
# Reachable from non-interactive sessions too (`kvbox connect box -- claude ...`).
RUN ln -s /home/kvbox/.local/bin/claude /usr/local/bin/claude

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
    # Docker starts on the first `docker` command (socket activation), not at boot: keeps boot fast.
    && systemctl enable docker.socket && systemctl disable docker.service containerd.service \
    # Mask, don't disable: presets re-enable disabled units on first boot (seen in spike #4).
    && systemctl mask systemd-resolved.service systemd-timesyncd.service \
         apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer \
         e2scrub_all.timer e2scrub_reap.service motd-news.timer
