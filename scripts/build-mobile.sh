#!/usr/bin/env bash
# Reproducible release build for the Flutter employee app.
#
#   scripts/build-mobile.sh aab     Play Store bundle (default)
#   scripts/build-mobile.sh apk     per-ABI APKs for sideloading
#   scripts/build-mobile.sh both
#
# Credentials come from the environment, or from apps/mobile/.env. They are
# compiled in via --dart-define; nothing is read from disk at runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/apps/mobile_flutter"
TARGET="${1:-aab}"

# --- credentials -----------------------------------------------------------
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  ENV_FILE="$ROOT/apps/mobile/.env"
  if [[ -f "$ENV_FILE" ]]; then
    set -a; . "$ENV_FILE"; set +a
    SUPABASE_URL="${SUPABASE_URL:-${EXPO_PUBLIC_SUPABASE_URL:-}}"
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-${EXPO_PUBLIC_SUPABASE_ANON_KEY:-}}"
  fi
fi
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set (or present in apps/mobile/.env)." >&2
  echo "Without them the app builds, installs, and shows only 'Not configured'." >&2
  exit 1
fi

# --- toolchain -------------------------------------------------------------
# macOS ships a /usr/bin/java stub that exists but fails when invoked, so test
# that java actually runs rather than that it is on the path.
if [[ -z "${JAVA_HOME:-}" ]] && ! java -version >/dev/null 2>&1; then
  for candidate in \
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [[ -d "$candidate" ]]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      echo "Using JDK at $JAVA_HOME"
      break
    fi
  done
  if ! java -version >/dev/null 2>&1; then
    echo "ERROR: no working JDK found. Install one, e.g. brew install openjdk@17" >&2
    exit 1
  fi
fi

# --- signing ---------------------------------------------------------------
if [[ ! -f "$APP/android/key.properties" ]]; then
  echo "WARNING: android/key.properties not found." >&2
  echo "         This build is signed with the DEBUG key and cannot be" >&2
  echo "         published. See android/key.properties.example." >&2
fi

cd "$APP"

# Fail before a long build rather than after.
echo "==> Static analysis"
flutter analyze
echo "==> Tests"
flutter test

DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
)

build_aab() {
  echo "==> App bundle"
  flutter build appbundle --release "${DEFINES[@]}"
  ls -lh build/app/outputs/bundle/release/*.aab
}

build_apk() {
  echo "==> APKs (split per ABI)"
  flutter build apk --release --split-per-abi "${DEFINES[@]}"
  ls -lh build/app/outputs/flutter-apk/*.apk
}

case "$TARGET" in
  aab)  build_aab ;;
  apk)  build_apk ;;
  both) build_aab; build_apk ;;
  *) echo "Usage: $0 [aab|apk|both]" >&2; exit 1 ;;
esac

echo "Done."
