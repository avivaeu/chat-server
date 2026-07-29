#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GIT_SHA="${GIT_SHA:-$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo local)}"

ELEMENT_CALL_REF="${ELEMENT_CALL_REF:-v0.20.0}"
VITE_PRODUCT_NAME="${VITE_PRODUCT_NAME:-Aviva Call}"
VITE_APP_VERSION="${VITE_APP_VERSION:-${ELEMENT_CALL_REF}-aviva1-${GIT_SHA}}"

GAR_PROJECT="${GAR_PROJECT:-gen-lang-client-0990085838}"
GAR_LOCATION="${GAR_LOCATION:-europe-west1}"
GAR_REPOSITORY="${GAR_REPOSITORY:-pentecostes}"
IMAGE_NAME="${IMAGE_NAME:-guest-element-call}"
IMAGE_TAG="${IMAGE_TAG:-${ELEMENT_CALL_REF}-aviva1-${GIT_SHA}}"

IMAGE_REF="${GAR_LOCATION}-docker.pkg.dev/${GAR_PROJECT}/${GAR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"

gcloud auth configure-docker "${GAR_LOCATION}-docker.pkg.dev" --quiet >/dev/null

docker buildx build \
  --platform linux/amd64 \
  --tag "${IMAGE_REF}" \
  --build-arg ELEMENT_CALL_REF="${ELEMENT_CALL_REF}" \
  --build-arg VITE_PRODUCT_NAME="${VITE_PRODUCT_NAME}" \
  --build-arg VITE_APP_VERSION="${VITE_APP_VERSION}" \
  --push \
  -f "${SCRIPT_DIR}/../element-call/Dockerfile" \
  "${SCRIPT_DIR}/../element-call"

printf 'Pushed %s\n' "${IMAGE_REF}"
