#!/usr/bin/env sh
set -eu

: "${SOURCE_URL:?SOURCE_URL is required.}"
: "${DESTINATION_URL:?DESTINATION_URL is required.}"

azcopy copy "$SOURCE_URL" "$DESTINATION_URL" \
  --recursive=true \
  --from-to=FileFile \
  --overwrite=ifSourceNewer
