#!/usr/bin/env bash
# Despliega TODA la plataforma de la PoC desde un proyecto GCP vacio (con facturacion):
#   1. bucket del estado  2. bootstrap (org Apigee X, instancia, LB+PSC, certificado, vault, SAs)
#   3. valores del vault  4. imagen del mock  5. ambientes  6. validacion de plataforma
# Las APIs (proxies, target servers, KVM, productos) las despliega el pipeline de su propio repo.
# Idempotente: se puede re-ejecutar.
# Uso: PROJECT_ID=mi-proyecto [APIGEE_NAME=poc] [REGION=us-central1] [DOMAIN=] [ENVIRONMENTS="dev qa"] scripts/up.sh
#   ENVIRONMENTS = ambientes de la org (org de evaluacion: maximo 2). Ej. otra org: ENVIRONMENTS="staging prod"
#   PLAN_ONLY=1  = solo bucket + terraform plan del bootstrap (no aplica nada; para revisar antes del apply)
#   APIGEE_NAME = nombre base de la plataforma (VPC, instancia, LB, certificado, registro, vault, SAs)
#   SUBNET_CIDR (10.10.0.0/24) y PEERING_CIDR (10.20.0.0/22): rangos de la VPC dedicada <name>-vpc
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
export PROJECT_ID=${PROJECT_ID:?PROJECT_ID requerido} REGION=${REGION:-us-central1} APIGEE_NAME=${APIGEE_NAME:-poc}
export STATE_BUCKET=${STATE_BUCKET:-${PROJECT_ID}-tfstate} APIGEE_ORG=$PROJECT_ID
export ENVIRONMENTS=${ENVIRONMENTS:-dev qa}   # lo usan tambien bootstrap_secrets.sh y check_platform.sh
read -r -a ENV_LIST <<<"$ENVIRONMENTS"
if [[ "${BILLING_TYPE:-EVALUATION}" == "EVALUATION" && ${#ENV_LIST[@]} -gt 2 ]]; then
  echo "una org de evaluacion admite maximo 2 ambientes (pedidos: ${ENVIRONMENTS})"; exit 1
fi
# HCL: lista para el bootstrap y mapa para la capa de ambientes (mismos valores que los defaults para dev/qa)
TF_ENV_LIST=$(printf '"%s", ' "${ENV_LIST[@]}"); TF_ENV_LIST="[${TF_ENV_LIST%, }]"
TF_ENV_MAP=$(for e in "${ENV_LIST[@]}"; do
  printf '  %s = { envgroup = "eg-%s", mock_service = "mock-customers-%s", truststore = "ts-backend-%s" }\n' "$e" "$e" "$e" "$e"
done)
source scripts/lib/tf.sh
step() { printf '\n\033[1m==> [%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
T0=$(date +%s)

step "0/6 Prerrequisitos"
for t in gcloud terraform jq curl openssl; do command -v $t >/dev/null || { echo "falta $t"; exit 1; }; done
[[ "$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)')" == "True" ]] || { echo "el proyecto no tiene facturacion"; exit 1; }
gcloud config set project "$PROJECT_ID" >/dev/null
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com storage.googleapis.com --project "$PROJECT_ID"

step "1/6 Bucket del estado de Terraform: gs://${STATE_BUCKET}"
gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1 || {
  gcloud storage buckets create "gs://${STATE_BUCKET}" --project "$PROJECT_ID" --location "$REGION" --uniform-bucket-level-access
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
}

step "2/6 [${APIGEE_NAME}] Bootstrap: org Apigee X + instancia + LB/PSC + certificado + vault + SAs (30-60 min la primera vez)"
cat > terraform/bootstrap/terraform.tfvars <<TFV
name         = "${APIGEE_NAME}"
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
billing_type = "${BILLING_TYPE:-EVALUATION}"
environments = ${TF_ENV_LIST}
domain       = "${DOMAIN:-}"
subnet_cidr  = "${SUBNET_CIDR:-10.10.0.0/24}"
peering_cidr = "${PEERING_CIDR:-10.20.0.0/22}"
TFV
tf_init terraform/bootstrap
if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
  tf terraform/bootstrap plan -input=false -no-color | tee bootstrap-plan.txt
  step "PLAN_ONLY: no se aplico nada (plan en bootstrap-plan.txt)"; exit 0
fi
tf terraform/bootstrap apply -input=false -auto-approve
tf terraform/bootstrap output hostnames

step "3/6 Valores del vault (Secret Manager; nunca se muestran)"
scripts/bootstrap_secrets.sh

step "4/6 Imagen del backend mock (Cloud Build -> Artifact Registry)"
TAG=$(jq -r .version mock/package.json)
gcloud artifacts docker images describe "${REGION}-docker.pkg.dev/${PROJECT_ID}/${APIGEE_NAME}/mock-customers:${TAG}" >/dev/null 2>&1 \
  && echo "imagen mock-customers:${TAG} ya existe" || scripts/build_mock.sh "$TAG"

step "5/6 Ambientes ${ENVIRONMENTS}: Apigee envs + env groups + attachments + Cloud Run + truststores"
cat > terraform/environments/terraform.tfvars <<TFV
project_id     = "${PROJECT_ID}"
region         = "${REGION}"
state_bucket   = "${STATE_BUCKET}"
mock_image_tag = "${TAG}"
environments = {
${TF_ENV_MAP}
}
TFV
tf_init terraform/environments
tf terraform/environments apply -input=false -auto-approve

step "6/6 Validacion de plataforma (espera la emision del certificado si hace falta)"
HOSTNAMES=$(tf terraform/bootstrap output -json hostnames | jq -r 'to_entries[].value') scripts/check_platform.sh --wait-cert

step "LISTO en $(( ($(date +%s) - T0) / 60 )) min"
tf terraform/bootstrap output -json hostnames | jq -r 'to_entries[] | "  \(.key): https://\(.value)/v1/poc-customer/customers"'
echo "Siguiente: PROJECT_ID=${PROJECT_ID} scripts/setup_github.sh <owner/repo-de-APIs>"
