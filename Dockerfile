# Pinned versions matching Expo SDK 57 build requirements
ARG VERSION=2.337.0-ubuntu-noble
ARG JAVA_VERSION=17
ARG COMPILE_SDK=36
ARG BUILD_TOOLS=36.0.0
ARG NDK_VERSION=27.1.12297006
ARG CMAKE_VERSION=3.22.1
ARG SDK_TOOLS=11076708_latest
ARG NODE_VERSION=22.23.1
ARG PNPM_VERSION=11.9.0
ARG EAS_CLI_VERSION=24.7.0
ARG ANDROID_ROOT=/usr/local/lib/android

################################################################################
# Stage 1: Base runner image from myoung34/github-runner with Temurin Java 17
################################################################################
FROM myoung34/github-runner:$VERSION AS java
ARG JAVA_VERSION

# Set up Adoptium Temurin JDK repository
RUN mkdir -p /etc/apt/keyrings && \
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | tee /etc/apt/keyrings/adoptium.asc >/dev/null && \
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

# Install Temurin JDK 17, native compilation tools and utilities
RUN apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  temurin-${JAVA_VERSION}-jdk \
  iproute2 \
  build-essential \
  swig \
  curl \
  wget \
  unzip \
  xz-utils \
  git \
  jq \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-${JAVA_VERSION}-jdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

################################################################################
# Stage 2: Install Android SDK, NDK, Build Tools, and CMake 3.22.1
################################################################################
FROM java AS android
ARG COMPILE_SDK
ARG BUILD_TOOLS
ARG NDK_VERSION
ARG CMAKE_VERSION
ARG SDK_TOOLS
ARG ANDROID_ROOT

WORKDIR /tmp

# Download Android cmdline-tools and accept licenses
RUN mkdir -p ${ANDROID_ROOT}/sdk/cmdline-tools/latest && \
  wget -qO android-sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-${SDK_TOOLS}.zip && \
  unzip -q android-sdk.zip && \
  cp -r ./cmdline-tools/* ${ANDROID_ROOT}/sdk/cmdline-tools/latest && \
  rm -rf ./cmdline-tools android-sdk.zip

RUN echo "y" | ${ANDROID_ROOT}/sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_ROOT}/sdk/ --licenses >/dev/null

# Install exact Android SDK components required for Expo SDK 57 (idempotent with retry)
RUN attempt=1; \
  until echo "y" | ${ANDROID_ROOT}/sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_ROOT}/sdk/ \
    "platform-tools" \
    "platforms;android-${COMPILE_SDK}" \
    "build-tools;${BUILD_TOOLS}" \
    "ndk;${NDK_VERSION}" \
    "cmake;${CMAKE_VERSION}"; do \
    if [ "$attempt" -ge 3 ]; then echo "sdkmanager failed after $attempt attempts" >&2; exit 1; fi; \
    echo "sdkmanager attempt $attempt failed, retrying in 15s..." >&2; \
    rm -rf ${ANDROID_ROOT}/sdk/.temp; \
    attempt=$((attempt + 1)); \
    sleep 15; \
  done

# Symlink standard SDK root to /opt/android-sdk for compatibility across environments
RUN ln -s ${ANDROID_ROOT}/sdk /opt/android-sdk

# Symlink Android CMake 3.22.1 to /usr/local/bin to guarantee CMake 3.22.1 precedence
RUN ln -sf ${ANDROID_ROOT}/sdk/cmake/3.22.1/bin/cmake /usr/local/bin/cmake && \
  ln -sf ${ANDROID_ROOT}/sdk/cmake/3.22.1/bin/ninja /usr/local/bin/ninja

ENV ANDROID_SDK_ROOT=${ANDROID_ROOT}/sdk
ENV ANDROID_HOME=${ANDROID_ROOT}/sdk

################################################################################
# Stage 3: Install Node.js 22.23.1, Corepack, pnpm 11.9.0, EAS CLI
################################################################################
FROM android AS expo-runner
ARG NODE_VERSION
ARG PNPM_VERSION
ARG EAS_CLI_VERSION
ARG ANDROID_ROOT

WORKDIR /tmp

# Install exact Node.js 22.23.1 from official distribution
RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -o node.tar.xz && \
  tar -xJf node.tar.xz -C /usr/local --strip-components=1 --no-same-owner && \
  rm -f node.tar.xz

# Enable Corepack and activate exact pnpm 11.9.0
RUN corepack enable && \
  corepack prepare pnpm@${PNPM_VERSION} --activate

# Install pinned EAS CLI globally
RUN npm install -g eas-cli@${EAS_CLI_VERSION}

# Prepare persistent volume cache and work directories
RUN mkdir -p /root/.gradle /root/.m2 /root/.npm /root/.local/share/pnpm /root/.expo \
  /runner-data /runner/_work /scripts /artifacts

# Configure PATH with CMake 3.22.1, Android tools, Java, and local binaries
ENV PATH="/usr/local/lib/android/sdk/cmake/3.22.1/bin:/usr/local/lib/android/sdk/cmdline-tools/latest/bin:/usr/local/lib/android/sdk/platform-tools:/usr/local/lib/android/sdk/build-tools/36.0.0:${JAVA_HOME}/bin:${PATH}"

# Copy environment verification script
COPY scripts/verify-ci-environment.sh /scripts/verify-ci-environment.sh
RUN chmod +x /scripts/verify-ci-environment.sh && \
  ln -sf /scripts/verify-ci-environment.sh /usr/local/bin/verify-ci-environment.sh

# Post-job cleanup hook to prevent unbounded cache growth
COPY cleanup.sh /usr/local/bin/cleanup.sh
RUN chmod +x /usr/local/bin/cleanup.sh
ENV ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/usr/local/bin/cleanup.sh

# Preflight entrypoint to validate persisted runner registration
COPY preflight-entrypoint.sh /usr/local/bin/preflight-entrypoint.sh
RUN chmod +x /usr/local/bin/preflight-entrypoint.sh

# Verify all tooling at build time
RUN /scripts/verify-ci-environment.sh

WORKDIR /actions-runner
LABEL maintainer="tamdinh"
LABEL description="Self-hosted GitHub Actions runner for Expo SDK 57, Android (API 36, NDK 27), and Web"

ENTRYPOINT ["/usr/local/bin/preflight-entrypoint.sh"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]
