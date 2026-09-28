#!/usr/bin/env bash
# Named Firestore database + TTL policy on roasts.expiresAt.
source "$(dirname "$0")/env.sh"

say "Firestore database '$FIRESTORE_DB'"
if ! exists gcloud firestore databases describe --database="$FIRESTORE_DB"; then
  gcloud firestore databases create --database="$FIRESTORE_DB" --location="$REGION" --type=firestore-native
fi

say "TTL policy: roasts.expiresAt"
# TTL deletes lazily (usually within 24 h of expiry); the API also checks expiresAt itself.
gcloud firestore fields ttls update expiresAt --collection-group=roasts --enable-ttl \
  --database="$FIRESTORE_DB" --async --quiet
