#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <production.apk>" >&2
  exit 2
fi

apk=$1
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
metadata_file="$repo_dir/tool/production_signing.env"

if [ ! -f "$apk" ]; then
  echo "APK not found: $apk" >&2
  exit 2
fi

# shellcheck disable=SC1090
. "$metadata_file"

sdk_root=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
build_tools_dir=$(find "$sdk_root/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
apksigner="$build_tools_dir/apksigner"
aapt="$build_tools_dir/aapt"

if [ ! -x "$apksigner" ] || [ ! -x "$aapt" ]; then
  echo "Android build-tools (apksigner/aapt) not found." >&2
  exit 2
fi

actual_cert=$(
  "$apksigner" verify --print-certs "$apk" |
    sed -n 's/^Signer #1 certificate SHA-256 digest: //p' |
    head -1 |
    tr '[:upper:]' '[:lower:]'
)
badge=$("$aapt" dump badging "$apk" | sed -n '1p')
actual_package=$(printf '%s\n' "$badge" | awk '{v=$2; sub(/^name=\047/, "", v); sub(/\047$/, "", v); print v}')
actual_label=$(
  "$aapt" dump badging "$apk" |
    sed -n "s/^application-label:'\([^']*\)'$/\1/p" |
    head -1
)

if [ "$actual_cert" != "$PRODUCTION_CERT_SHA256" ]; then
  echo "ERROR: APK signer does not match the production certificate." >&2
  exit 1
fi

if [ "$actual_package" != "$PRODUCTION_APPLICATION_ID" ]; then
  echo "ERROR: APK package is not the production application ID." >&2
  exit 1
fi

if [ "$actual_label" != "$PRODUCTION_APPLICATION_LABEL" ]; then
  echo "ERROR: APK label does not match the approved production label." >&2
  exit 1
fi

if printf '%s\n' "$actual_package" | grep -q '\.qa$'; then
  echo "ERROR: QA package cannot be released as production." >&2
  exit 1
fi

if "$aapt" dump xmltree "$apk" AndroidManifest.xml | grep -q 'android:debuggable.*0xffffffff'; then
  echo "ERROR: production APK is debuggable." >&2
  exit 1
fi

if ! "$aapt" dump badging "$apk" | grep -q '^application-icon-'; then
  echo "ERROR: production APK does not expose launcher icons." >&2
  exit 1
fi

resources=$("$aapt" dump resources "$apk")
for resource in 'mipmap/ic_launcher' 'mipmap/ic_launcher_round' 'drawable/launcher_icon_foreground'; do
  if ! printf '%s\n' "$resources" | grep -q "$resource"; then
    echo "ERROR: production APK is missing $resource." >&2
    exit 1
  fi
done

echo "Production APK signing verification passed."
