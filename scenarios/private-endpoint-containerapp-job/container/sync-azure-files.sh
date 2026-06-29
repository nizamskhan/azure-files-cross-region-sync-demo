#!/usr/bin/env sh
set -eu

: "${SOURCE_URL:?SOURCE_URL is required.}"
: "${DESTINATION_URL:?DESTINATION_URL is required.}"

if [ -n "${AZCOPY_AUTO_LOGIN_IDENTITY_CLIENT_ID:-}" ]; then
  azcopy login --identity --identity-client-id "$AZCOPY_AUTO_LOGIN_IDENTITY_CLIENT_ID"
else
  azcopy login --identity
fi

azcopy copy "$SOURCE_URL" "$DESTINATION_URL" \
  --recursive=true \
  --from-to=FileFile \
  --overwrite=ifSourceNewer
