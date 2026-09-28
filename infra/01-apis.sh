#!/usr/bin/env bash
# Enables every API Roastfolio uses.
source "$(dirname "$0")/env.sh"

say "Enabling APIs"
gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  firestore.googleapis.com storage.googleapis.com compute.googleapis.com \
  cloudtasks.googleapis.com documentai.googleapis.com aiplatform.googleapis.com \
  secretmanager.googleapis.com iam.googleapis.com logging.googleapis.com monitoring.googleapis.com
