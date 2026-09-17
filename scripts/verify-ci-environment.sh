#!/usr/bin/env bash

set -euo pipefail

echo "================================================================="
echo "        Expo SDK 57 CI Environment Verification"
echo "================================================================="

FAILED=0

check_cmd() {
  local name="$1"
  local cmd="$2"
  local expected="${3:-}"
  echo -n "Checking $name... "
  if ! output=$(eval "$cmd" 2>&1); then
    echo "FAILED"
    echo "  Command failed: $cmd"
    echo "  Output: $output"
    FAILED=1
    return 1
  fi

  if [ -n "$expected" ]; then
    if echo "$output" | grep -qE "$expected"; then
      echo "OK (matches '$expected')"
    else
      echo "FAILED"
      echo "  Expected to match: $expected"
      echo "  Actual output: $output"
      FAILED=1
      return 1
    fi
  else
    echo "OK"
  fi
}

echo "=== System & User ==="
echo "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo "HOME: $HOME"
echo "Workdir: $(pwd)"

echo ""
echo "=== Core Runtime & Tooling ==="
check_cmd "Java 17" "java -version" "openjdk version \"17\.|Temurin-17\."
check_cmd "JAVA_HOME" "echo \$JAVA_HOME" "/usr/lib/jvm"
check_cmd "Node.js 22.23.1" "node --version" "v22\.23\.1"
check_cmd "npm" "npm --version" "^[0-9]"
check_cmd "Corepack" "corepack --version" "^[0-9]"
check_cmd "pnpm 11.9.0" "pnpm --version" "11\.9\.0"
check_cmd "EAS CLI" "eas --version" "eas-cli/[0-9]+"

echo ""
echo "=== Android SDK & Build Tools ==="
check_cmd "ANDROID_HOME" "echo \$ANDROID_HOME" ".+"
check_cmd "ANDROID_SDK_ROOT" "echo \$ANDROID_SDK_ROOT" ".+"
check_cmd "sdkmanager CLI" "sdkmanager --version" "^[0-9]"
check_cmd "ADB CLI" "adb version" "Android Debug Bridge version"
check_cmd "CMake 3.22.1" "cmake --version" "cmake version 3\.22\.1"

echo ""
echo "=== Required Android Components ==="
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"

check_component() {
  local label="$1"
  local check_path="$2"
  echo -n "Checking $label... "
  if [ -e "$check_path" ]; then
    echo "OK ($check_path)"
  else
    echo "FAILED ($check_path not found)"
    FAILED=1
  fi
}

check_component "Platform Tools" "$SDK_DIR/platform-tools/adb"
check_component "Platform android-36" "$SDK_DIR/platforms/android-36/android.jar"
check_component "Build Tools 36.0.0" "$SDK_DIR/build-tools/36.0.0/aapt2"
check_component "NDK 27.1.12297006" "$SDK_DIR/ndk/27.1.12297006/source.properties"
check_component "CMake 3.22.1" "$SDK_DIR/cmake/3.22.1/bin/ninja"

echo ""
echo "=== Installed Packages via sdkmanager ==="
if [ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
  INSTALLED_PKGS=$("$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" --list_installed 2>/dev/null || true)
  echo "Verified installed packages:"
  echo "$INSTALLED_PKGS" | grep -E "platforms;android-36|build-tools;36.0.0|ndk;27.1.12297006|cmake;3.22.1|platform-tools" || true
fi

echo ""
echo "================================================================="
if [ "$FAILED" -eq 0 ]; then
  echo "ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!"
  echo "The environment is fully configured for Expo SDK 57 builds."
  echo "================================================================="
  exit 0
else
  echo "ONE OR MORE CHECKS FAILED! Review output above."
  echo "================================================================="
  exit 1
fi
