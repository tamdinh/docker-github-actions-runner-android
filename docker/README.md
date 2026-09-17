# Expo SDK 57 Self-Hosted GitHub Actions Runner

Production-ready, Docker-based self-hosted GitHub Actions runner engineered specifically for **Expo SDK 57** projects. It bakes the complete Android SDK, NDK, Java 17, and Node.js/pnpm/EAS environment directly into the container image—eliminating dynamic downloads during runtime and ensuring fast, reproducible CI/CD pipelines.

Supported build outputs:
- **Expo / React Native Android**: Development APK, Preview APK, and Production AAB via EAS Local Build.
- **Expo Web**: Static web exports (`dist/`).
- **Target Hosting**: Deployable on any Linux VPS or container platform using Docker, Docker Compose, or **Dokploy**.

---

## Architecture Overview

```text
┌─────────────────────────────────────────────────────┐
│                    Dokploy / VPS                    │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │           Expo GitHub Actions Runner          │  │
│  │                                               │  │
│  │  GitHub Actions Self-hosted Runner (v2.337.0) │  │
│  │  Ubuntu 24.04 (Noble)                         │  │
│  │                                               │  │
│  │  Java 17 (Eclipse Temurin)                    │  │
│  │  Android SDK API 36 (platforms;android-36)    │  │
│  │  Android Build Tools 36.0.0                   │  │
│  │  Android NDK 27.1.12297006                    │  │
│  │  CMake 3.22.1                                 │  │
│  │                                               │  │
│  │  Node.js 22.23.1                              │  │
│  │  Corepack + pnpm 11.9.0                       │  │
│  │  EAS CLI 24.7.0                               │  │
│  │                                               │  │
│  │  Preflight Re-registration Protection         │  │
│  │  Automated Post-Job Cache Cleanup Hook        │  │
│  └───────────────────────────────────────────────┘  │
│                         │                           │
│              Persistent Docker Volumes              │
│                         │                           │
│    ┌──────────────┬─────┴────────┬──────────────┐   │
│    │              │              │              │   │
│ Gradle cache  Maven cache    pnpm cache    Runner data
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 1. Tooling & Version Matrix

All tooling is strictly pinned and **baked into the Docker image at build time**. The container never downloads the Android SDK, Java, or Node.js during startup.

| Component | Pinned Version | Purpose / Notes |
| :--- | :--- | :--- |
| **Base OS** | Ubuntu 24.04 LTS (Noble) | Standard runner base (`myoung34/github-runner`) |
| **Java JDK** | Eclipse Temurin 17 | Required for Expo SDK 57 & AGP compatibility |
| **Node.js** | 22.23.1 | Exact LTS release from official binary distribution |
| **Package Manager** | pnpm 11.9.0 | Managed and activated via Node Corepack |
| **Android SDK** | API Level 36 (`android-36`) | Required compileSdk for React Native 0.86 / Expo 57 |
| **Build Tools** | 36.0.0 | Compatible Android build tools |
| **Android NDK** | 27.1.12297006 | Pinned NDK release for React Native native builds |
| **CMake** | 3.22.1 | Native Android build integration |
| **EAS CLI** | 24.7.0 | Expo Application Services CLI for EAS Local builds |
| **GitHub Runner** | 2.337.0 | Self-hosted runner agent with preflight validation |

---

## 2. Directory Structure

```text
.
├── Dockerfile                      # Production Dockerfile with multi-stage build
├── docker-compose.yml              # Production Compose definition with persistent volumes
├── .env.example                    # Template for runner authentication and settings
├── README.md                       # Comprehensive guide and documentation
├── cleanup.sh                      # Post-job hook to clean ephemeral build caches
├── preflight-entrypoint.sh         # Validates persisted registration against GitHub API
├── scripts/
│   └── verify-ci-environment.sh    # Rigorous environment verification script
├── docker/                         # Subdirectory with mirrored configuration
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── README.md
│   ├── cleanup.sh
│   ├── preflight-entrypoint.sh
│   └── scripts/
│       └── verify-ci-environment.sh
└── .github/
    └── workflows/
        ├── build-android.yml       # Local EAS build workflow (APK & AAB)
        ├── build-web.yml           # Static web export workflow
        └── build-all.yml           # Unified build workflow
```

---

## 3. Prerequisites

- **Host**: Linux VPS or Dokploy host (Ubuntu 22.04+ or Debian 12+ recommended).
- **Docker Engine**: Docker 24.0+ and Docker Compose v2.20+.
- **GitHub Repository**: Admin or repository access to generate a runner token or Personal Access Token (PAT).
- **Hardware Sizing**:
  - Minimum: 2 vCPUs, 4 GB RAM, 20 GB free disk.
  - Recommended: 4+ vCPUs, 8+ GB RAM, 50 GB free disk (for fast Android Gradle/NDK compilation).

---

## 4. Configuration

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your repository details:
   ```ini
   # GitHub Repository URL
   REPO_URL=https://github.com/your-org/your-repo

   # Authentication: choose EITHER a runner registration token OR personal access token
   # Option A: Registration token (from Settings > Actions > Runners > New runner)
   RUNNER_TOKEN=your_runner_registration_token

   # Option B (Recommended for preflight resilience): GitHub PAT with repo/admin:org scope
   # ACCESS_TOKEN=ghp_your_pat_token

   # Runner Identity
   RUNNER_NAME=expo-android-runner
   RUNNER_LABELS=self-hosted,linux,x64,expo,android,web,vps
   RUNNER_WORKDIR=/runner/_work

   # Persistence
   CONFIGURED_ACTIONS_RUNNER_FILES_DIR=/runner-data
   DISABLE_AUTOMATIC_DEREGISTRATION=true
   ```

---

## 5. Build and Run

### Step 1: Build the Image
```bash
docker compose build
```
This builds image `expo-runner:expo57-node22-android36-v1` and runs the built-in `/scripts/verify-ci-environment.sh` verification at the final build step.

### Step 2: Start the Runner
```bash
docker compose up -d
```

### Step 3: Monitor Logs
```bash
docker logs -f github-expo-runner
```
Expected output:
```text
[preflight] ACCESS_TOKEN not set; cannot validate persisted registration, leaving as-is (or checking registration)
...
Runner successfully registered
Runner connected
Listening for Jobs
```

### Step 4: Verify the Container Environment
Run the included verification script inside the running container:
```bash
docker exec github-expo-runner /scripts/verify-ci-environment.sh
```
All checks must output `OK` and finish with `ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!`.

---

## 6. Dokploy Deployment Guide

To deploy this runner via [Dokploy](https://dokploy.com):

1. **Create Application in Dokploy**:
   - Choose **Docker Compose** as the deployment type.
   - Connect your Git repository (`docker-github-actions-runner-android`).
   - Specify the Compose path: `docker-compose.yml` (or `docker/docker-compose.yml`).
2. **Configure Environment Variables**:
   - Under the **Environment** tab in Dokploy, paste the values from `.env.example`:
     - `REPO_URL`
     - `RUNNER_TOKEN` (or `ACCESS_TOKEN`)
     - `RUNNER_NAME`
     - `RUNNER_LABELS`
     - `CONFIGURED_ACTIONS_RUNNER_FILES_DIR=/runner-data`
     - `DISABLE_AUTOMATIC_DEREGISTRATION=true`
3. **Configure Volumes**:
   - The volumes defined in `docker-compose.yml` (`runner-data`, `gradle-cache`, `maven-cache`, `pnpm-cache`, `expo-cache`) will automatically be created and managed by Dokploy.
4. **Deploy**:
   - Click **Deploy**. Dokploy will pull/build the image and launch the runner container.

---

## 7. Persistent Caching Strategy

The runner mounts persistent named volumes to cache expensive build artifacts between workflow jobs:

| Volume Name | Container Path | What It Stores |
| :--- | :--- | :--- |
| `runner-data` | `/runner-data` | Runner credentials & registration state (prevents duplicate registrations) |
| `gradle-cache` | `/root/.gradle` | Gradle wrapper downloads, dependency jars |
| `maven-cache` | `/root/.m2` | Maven repository artifacts |
| `npm-cache` | `/root/.npm` | Global npm cache |
| `pnpm-cache` | `/root/.local/share/pnpm` | Global pnpm content-addressable store |
| `expo-cache` | `/root/.expo` | EAS credentials and template caches |

### Automated Cache Maintenance
Between jobs, GitHub Actions invokes `cleanup.sh` via `ACTIONS_RUNNER_HOOK_JOB_COMPLETED`. This hook:
- Deletes transient `/tmp` files and temporary EAS local build directories.
- Prunes Gradle transform and journal caches (`~/.gradle/caches/build-cache-*`, `transforms-*`, `journal-*`).
- Kills stopped Gradle daemons (`~/.gradle/daemon/`).
- Preserves the downloaded dependencies in `~/.gradle/caches/modules-2/` and the pnpm store, saving gigabytes of bandwidth and minutes of build time per run.

---

## 8. GitHub Actions Workflows

Sample production workflows are included in `.github/workflows/`:

### 1. Android Build (`build-android.yml`)
- Triggers on `push` to `main` or manual trigger (`workflow_dispatch`).
- Supports selecting build profiles: `preview` (outputs APK) or `production` (outputs AAB).
- Validates environment using `verify-ci-environment.sh`.
- Installs dependencies using `pnpm install --frozen-lockfile`.
- Runs `pnpm exec expo-doctor`.
- Executes EAS Local build:
  ```bash
  eas build --platform android --profile preview --local --non-interactive --output ./artifacts/app-preview.apk
  ```
- Uploads the resulting APK/AAB via `actions/upload-artifact@v4`.

### 2. Web Build (`build-web.yml`)
- Triggers on `push` to `main` or manual trigger (`workflow_dispatch`).
- Installs dependencies and runs `pnpm exec expo export --platform web`.
- Uploads the generated `dist/` directory as a build artifact.

### 3. Combined Pipeline (`build-all.yml`)
- Executes both Android and Web builds concurrently with custom parameterization.

---

## 9. Upgrade and Rollback Strategy

Always avoid deploying with just `:latest`. Use explicit version tags.

### Tag Scheme
```text
expo-runner:expo57-node22-android36-v1
expo-runner:expo57-node22-android36-v2
```

### Upgrading the Environment:
1. Update version arguments in `Dockerfile` or `docker-compose.yml`.
2. Update the tag in `docker-compose.yml` to the new version (e.g. `v2`).
3. Build the new image:
   ```bash
   docker compose build
   ```
4. Test the new container:
   ```bash
   docker compose up -d
   docker exec github-expo-runner /scripts/verify-ci-environment.sh
   ```
5. Trigger a test workflow build on GitHub Actions.

### Rolling Back:
If a newly built image causes compatibility regressions:
1. Revert the image tag in `docker-compose.yml` to the previous known good tag (e.g. `v1`).
2. Re-launch the container:
   ```bash
   docker compose up -d
   ```
The persistent volume mounts preserve your runner registration and dependencies across image updates.

---

## 10. Security Best Practices

1. **No Docker Socket**: `/var/run/docker.sock` is **not** mounted inside the container. This prevents arbitrary workflows from escaping the container to the host.
2. **Restricted Repository Scope**: Use this self-hosted runner only for private repositories or trusted internal projects. Do not allow public pull requests from untrusted forks to execute jobs on self-hosted runners.
3. **Secrets Management**: Secrets such as `EXPO_TOKEN`, `RUNNER_TOKEN`, or `ACCESS_TOKEN` must never be committed to Git. Store them in `.env` (which is git-ignored) or in Dokploy environment variables.
