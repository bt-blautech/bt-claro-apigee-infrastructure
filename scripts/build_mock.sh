#!/usr/bin/env bash
# Construye la imagen del backend mock con Cloud Build y la publica en Artifact Registry.
# Uso: scripts/build_mock.sh [tag]   (por defecto, el contenido de mock/package.json -> version)
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT=${PROJECT_ID:?PROJECT_ID requerido}
REGION=${REGION:-us-central1}
TAG=${1:-$(python3 -c "import json;print(json.load(open('mock/package.json'))['version'])")}
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${APIGEE_NAME:?APIGEE_NAME requerido}/mock-customers:${TAG}"
# SA y bucket propios del build (terraform/bootstrap/platform.tf): no usa la SA por defecto de Compute
BUILD_SA="${APIGEE_NAME}-build@${PROJECT}.iam.gserviceaccount.com"
BUILD_BUCKET="gs://${PROJECT}-${APIGEE_NAME}-build"
gcloud builds submit mock --project "$PROJECT" --region "$REGION" --tag "$IMAGE" --quiet \
  --service-account "projects/${PROJECT}/serviceAccounts/${BUILD_SA}" \
  --gcs-source-staging-dir "${BUILD_BUCKET}/source" --gcs-log-dir "${BUILD_BUCKET}/logs"
echo "imagen: $IMAGE"
