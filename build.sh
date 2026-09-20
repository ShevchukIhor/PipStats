#!/usr/bin/env bash
# Build script that auto-loads defines.env for dart defines
# Usage: ./build.sh [--install]

set -e

INSTALL=true
FLUTTER_ARGS=()
for arg in "$@"; do
  case $arg in
    --install) INSTALL=true ;;
    *) FLUTTER_ARGS+=("$arg") ;;
  esac
done

DEFINES_FILE="defines.env"
if [[ -f "$DEFINES_FILE" ]]; then
  echo "Loading dart defines from $DEFINES_FILE"
  flutter build apk --release --dart-define-from-file="$DEFINES_FILE" "${FLUTTER_ARGS[@]}"
else
  echo "No $DEFINES_FILE found, building without extra defines"
  flutter build apk --release "${FLUTTER_ARGS[@]}"
fi

if [[ "$INSTALL" == true ]]; then
  APK=$(ls -t build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | head -1)
  if [[ -f "$APK" ]]; then
    echo "Installing $APK via adb..."
    adb install -r "$APK"
  else
    echo "APK not found, skipping install"
  fi
fi