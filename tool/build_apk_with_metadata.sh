#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
git_sha=$(git -C "$repo_dir" rev-parse HEAD)
build_date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)

flutter build apk \
  --dart-define="GIT_SHA=$git_sha" \
  --dart-define="BUILD_DATE_UTC=$build_date_utc" \
  "$@"

production_flavor=false
release_mode=true
previous=
for argument in "$@"; do
  if [ "$previous" = "--flavor" ] && [ "$argument" = "production" ]; then
    production_flavor=true
  fi
  case "$argument" in
    --flavor=production) production_flavor=true ;;
    --debug|--profile) release_mode=false ;;
    --release) release_mode=true ;;
  esac
  previous=$argument
done

if [ "$production_flavor" = true ] && [ "$release_mode" = true ]; then
  "$repo_dir/tool/verify_production_signing.sh" \
    "$repo_dir/build/app/outputs/flutter-apk/app-production-release.apk"
fi
