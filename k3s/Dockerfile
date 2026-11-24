# kvbox k3s image (kvbox #214): the base image plus k3s (Apache 2.0), the Kubernetes every box of a
# kvbox cluster runs, master and nodes alike. The binary and the images k3s needs to come up (coredns,
# traefik, local-path, metrics-server, klipper, pause: k3s's own "airgap" set) are from the k3s
# project's GitHub release, checksums pinned below, so nothing is downloaded when a box boots.
# Built by k3s/build.sh, which first builds base/ as kvbox-base:local; never run as a container.
#
# Nothing runs until the box owner's variables arrive: kvbox-k3s-init.service takes the role
# (K3S_ROLE=server|agent), the join token (K3S_TOKEN) and the rest, writes k3s's configuration and only
# then starts k3s.service.
FROM kvbox-base:local

# A new version: change it and the four checksums (sha256sum-amd64.txt and sha256sum-arm64.txt of the
# release: the lines for k3s / k3s-arm64 and k3s-airgap-images-<arch>.tar.zst).
ARG K3S_VERSION=v1.37.2+k3s1
ARG K3S_SHA256_X86_64=265b3ee6a3198ef14033c63ef46cbb32370d83795199fb6d1b01f21575eddbda
ARG K3S_SHA256_ARM64=a779ccf1e5e2e33a62f5a29c2f1c0bbf99431e100579d4c10f0aa0742a6aa84b
ARG K3S_IMAGES_SHA256_X86_64=35a5af1e69b57b8b627a4f6b1c29ea104209b661067b8c97fd40dc3f860bfcd2
ARG K3S_IMAGES_SHA256_ARM64=ca384f1a77aa83024bd82ad26fa4774971adb038e656a3b5b9af926be445a442
RUN case "$(uname -m)" in \
      x86_64)  bin=k3s;       arch=amd64; sum="$K3S_SHA256_X86_64"; isum="$K3S_IMAGES_SHA256_X86_64" ;; \
      aarch64) bin=k3s-arm64; arch=arm64; sum="$K3S_SHA256_ARM64";  isum="$K3S_IMAGES_SHA256_ARM64" ;; \
      *) echo "no k3s build for $(uname -m)" >&2; exit 1 ;; \
    esac \
    && url="https://github.com/k3s-io/k3s/releases/download/$(printf '%s' "$K3S_VERSION" | sed 's/+/%2B/')" \
    && curl -fsSL -o /usr/local/bin/k3s "$url/$bin" \
    && echo "$sum  /usr/local/bin/k3s" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/k3s \
    # The images are kept outside /var/lib/rancher, which is a mount of the box's disk once the box runs;
    # kvbox-k3s-mounts puts this directory where k3s looks for them.
    && install -d -m 0755 /usr/local/share/kvbox/k3s-images \
    && curl -fsSL -o "/usr/local/share/kvbox/k3s-images/k3s-airgap-images-$arch.tar.zst" "$url/k3s-airgap-images-$arch.tar.zst" \
    && echo "$isum  /usr/local/share/kvbox/k3s-images/k3s-airgap-images-$arch.tar.zst" | sha256sum -c - \
    && ln -s k3s /usr/local/bin/kubectl && ln -s k3s /usr/local/bin/crictl \
    && k3s --version | grep -qF "$K3S_VERSION"

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-k3s-init /usr/local/sbin/kvbox-k3s-mounts /usr/local/sbin/kvbox-k3s-run \
       /usr/local/sbin/kvbox-k3s-status /usr/local/sbin/kvbox-k3s-kubeconfig /usr/local/sbin/kvbox-k3s-drain \
       /usr/local/sbin/kvbox-k3s-rotate \
    && chmod 0644 /etc/kvbox/image.json /etc/systemd/system/k3s.service /etc/systemd/system/kvbox-k3s-init.service \
       /etc/systemd/system/kvbox-k3s-api.socket /etc/systemd/system/kvbox-k3s-api.service \
       /etc/sysctl.d/60-kvbox-k3s.conf \
    # The public API port's forwarder and what kvbox-k3s-rotate makes certificate authorities with.
    && test -x /usr/lib/systemd/systemd-socket-proxyd && command -v openssl >/dev/null \
    && systemctl enable k3s.service kvbox-k3s-init.service
