# kvbox android image: the base image plus what testing an Android app with Appium takes. Android itself
# runs as a Redroid container (Android's own processes on the box's kernel, nothing emulated), pulled and
# started at boot by kvbox-android.service, adb on 127.0.0.1:5555. Built by android/build.sh, which first
# builds base/ as kvbox-base:local; never run as a container.
#
# Redroid needs binder in the kernel: image.json names the android kernel (kernel-android/), so only boxes
# of this image boot it.
FROM kvbox-base:local

# What a new box starts with; Appium and its driver update with npm / `appium driver update`.
ARG CMDLINE_TOOLS=11076708
ARG BUILD_TOOLS=34.0.0
ARG APPIUM_VERSION=4.0.0
ARG UIAUTOMATOR2_VERSION=9.2.2

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jdk-headless maven unzip \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: command-line tools, platform-tools (adb) and build-tools (apksigner and aapt2, which
# Appium's UiAutomator2 driver uses). No platforms or system images: Android is the Redroid container.
ENV ANDROID_HOME=/opt/android-sdk
RUN curl -fsSL -o /tmp/clt.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
    && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && unzip -q /tmp/clt.zip -d "$ANDROID_HOME/cmdline-tools" && rm /tmp/clt.zip \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null \
    && "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "build-tools;${BUILD_TOOLS}" >/dev/null \
    && ln -s "$ANDROID_HOME/platform-tools/adb" /usr/local/bin/adb \
    && chown -R kvbox:kvbox "$ANDROID_HOME" \
    && adb version | head -1

# Appium with the UiAutomator2 driver (Android); drivers live in APPIUM_HOME, owned by kvbox.
ENV APPIUM_HOME=/opt/appium
RUN npm install -g --no-fund --no-audit "appium@${APPIUM_VERSION}" \
    && install -d -o kvbox -g kvbox "$APPIUM_HOME" \
    && runuser -u kvbox -- env APPIUM_HOME="$APPIUM_HOME" ANDROID_HOME="$ANDROID_HOME" \
         appium driver install --source=npm "appium-uiautomator2-driver@${UIAUTOMATOR2_VERSION}" \
    && rm -rf /root/.npm /home/kvbox/.npm \
    && appium --version

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/kvbox-android \
    && chmod 0644 /etc/kvbox/image.json /etc/profile.d/kvbox-android.sh \
    && systemctl enable kvbox-android.service kvbox-appium.service
