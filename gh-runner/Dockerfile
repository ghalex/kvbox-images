# kvbox gh-runner image (kvbox #100): the base image plus GitHub's Actions runner, unpacked and with its
# dependencies, registered at the first boot that has GITHUB_URL and GITHUB_RUNNER_TOKEN.
# Built by gh-runner/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# Docker and the kvbox user's docker group come from base. kvbox-gh-runner-init.service registers the
# runner once (config.sh) and installs it as a systemd service (svc.sh), which then starts at every boot.
FROM kvbox-base:local

# The runner updates itself when GitHub asks it to; this is only the version a new box starts with.
ARG RUNNER_VERSION=2.338.2

ENV DEBIAN_FRONTEND=noninteractive
# Tools GitHub's ubuntu-latest has and actions shell out to (action-shellcheck needs xz, for one).
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils zstd unzip jq zip \
    && rm -rf /var/lib/apt/lists/*

RUN install -d -o kvbox -g kvbox /home/kvbox/actions-runner \
    && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
       | runuser -u kvbox -- tar -xz -C /home/kvbox/actions-runner \
    && apt-get update && /home/kvbox/actions-runner/bin/installdependencies.sh \
    && rm -rf /var/lib/apt/lists/* \
    && test -x /home/kvbox/actions-runner/config.sh

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-gh-runner-init /usr/local/sbin/kvbox-idle \
    && chmod 0644 /etc/kvbox/image.json \
    && systemctl enable kvbox-gh-runner-init.service kvbox-docker-prune.timer
