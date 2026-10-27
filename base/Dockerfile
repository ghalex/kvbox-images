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
      less nano unzip \
      gnupg \
      nginx \
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

# Headless browser, so an agent in the box can open the page it is building: Chrome for Testing
# (Google's automation build of Chrome, the current Stable at build time) in /opt/chrome with the
# libraries and fonts it needs. Headless only: no display server, no GTK. Reached as `chromium`
# on PATH, and through AGENT_BROWSER_EXECUTABLE_PATH, set in /etc/environment so that PAM hands
# it to every SSH session, `kvbox connect box -- cmd` included. Chrome for Testing is published
# for x86_64 Linux only, like the kvbox guest kernel.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 \
      libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 \
      libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
      fonts-liberation fonts-noto-color-emoji fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/* \
    && url="$(curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json \
         | python3 -c 'import json,sys; c=json.load(sys.stdin)["channels"]["Stable"]; print(next(d["url"] for d in c["downloads"]["chrome"] if d["platform"]=="linux64"))')" \
    && curl -fsSL -o /tmp/chrome.zip "$url" \
    && unzip -q /tmp/chrome.zip -d /tmp/chrome && mv /tmp/chrome/chrome-linux64 /opt/chrome \
    && rm -rf /tmp/chrome /tmp/chrome.zip \
    && test -z "$(ldd /opt/chrome/chrome | grep 'not found')" \
    && ln -s /opt/chrome/chrome /usr/local/bin/chromium \
    && printf 'AGENT_BROWSER_EXECUTABLE_PATH=/opt/chrome/chrome\n' >> /etc/environment

# agent-browser (vercel-labs): the CLI agents drive the browser with (`agent-browser open <url>`,
# `snapshot`, `screenshot`, ...). A native binary; the daemon needs neither Node nor Playwright.
# Installed by exact version: the package declares Node >= 24, so on Node 22 a plain
# `npm install -g agent-browser` silently picks an old release, although nothing in it runs on Node.
RUN npm install -g "agent-browser@$(npm view agent-browser version)" \
    && agent-browser --version \
    # The package ships a binary for every platform; keep the one this image runs.
    && find /usr/lib/node_modules/agent-browser/bin -name 'agent-browser-*' ! -name 'agent-browser-linux-x64' ! -name '*.js' -delete \
    && rm -rf /root/.npm

# kvbox user: passwordless sudo, key-only SSH (the key arrives on the kernel cmdline, see kvbox-init).
# Drop the stock `ubuntu` user so kvbox is uid 1000.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash -G sudo,docker kvbox \
    && mkdir -p /home/kvbox/.ssh && chmod 700 /home/kvbox/.ssh && chown -R kvbox:kvbox /home/kvbox/.ssh

# Claude Code CLI and uv, installed as the kvbox user with their own installers: both land in
# ~/.local/bin (on PATH via Ubuntu's default ~/.profile) and update themselves from there.
USER kvbox
RUN HOME=/home/kvbox bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    && test -x /home/kvbox/.local/bin/claude
RUN HOME=/home/kvbox UV_NO_MODIFY_PATH=1 bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' \
    && test -x /home/kvbox/.local/bin/uv && test -x /home/kvbox/.local/bin/uvx
USER root
# Reachable from non-interactive sessions too (`kvbox connect box -- claude ...`).
RUN ln -s /home/kvbox/.local/bin/claude /usr/local/bin/claude \
    && ln -s /home/kvbox/.local/bin/uv /usr/local/bin/uv \
    && ln -s /home/kvbox/.local/bin/uvx /usr/local/bin/uvx

COPY rootfs/ /
RUN chmod 0440 /etc/sudoers.d/kvbox \
    # nginx serves /srv/app/dist for `kvbox deploy`: the site is wired, the service stays off until a
    # deploy turns it on. /srv/app belongs to kvbox so a deploy writes there without sudo.
    && rm -f /etc/nginx/sites-enabled/default \
    && ln -s /etc/nginx/sites-available/kvbox-app /etc/nginx/sites-enabled/kvbox-app \
    && mkdir -p /srv/app && chown kvbox:kvbox /srv/app \
    && systemctl disable nginx.service \
    && chmod 0755 /usr/local/sbin/kvbox-init /usr/local/sbin/kvbox-agent /sbin/overlay-init \
    # Mount points overlay-init needs: the box disk, and where the base image ends up after the
    # overlay becomes the root.
    && mkdir -p /overlay /rom \
    # Host keys are generated per box on first boot, never shared across boxes.
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
    # Generated on first boot too.
    && : > /etc/machine-id \
    # Clients forward LANG/LC_* over SSH and the image only has C.UTF-8: don't accept them,
    # and give the guest a sane default locale (kvbox issue #24).
    && sed -i 's/^AcceptEnv LANG LC_\*/#&/' /etc/ssh/sshd_config \
    && printf 'LANG=C.UTF-8\n' > /etc/default/locale \
    && systemctl enable ssh.service kvbox-init.service kvbox-agent.service \
    # Docker starts on the first `docker` command (socket activation), not at boot: keeps boot fast.
    && systemctl enable docker.socket && systemctl disable docker.service containerd.service \
    # Mask, don't disable: presets re-enable disabled units on first boot (seen in spike #4).
    && systemctl mask systemd-resolved.service systemd-timesyncd.service \
         apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer \
         e2scrub_all.timer e2scrub_reap.service motd-news.timer
