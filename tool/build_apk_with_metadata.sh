#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
git_sha=$(git -C "$repo_dir" rev-parse HEAD)
build_date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)

exec flutter build apk \
  --dart-define="GIT_SHA=$git_sha" \
  --dart-define="BUILD_DATE_UTC=$build_date_utc" \
  "$@"
