#!/usr/bin/env sh
set -eu

: "${SOURCE_URL:?SOURCE_URL is required.}"
: "${DESTINATION_URL:?DESTINATION_URL is required.}"

azcopy sync "$SOURCE_URL" "$DESTINATION_URL" \
  --recursive=true \
  --from-to=FileFile \
  --delete-destination=true
