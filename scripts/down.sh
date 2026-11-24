#!/usr/bin/env bash
# Elimina TODO lo creado por up.sh (irreversible): proxies desplegados, ambientes, Cloud Run,
# org Apigee X, instancia, LB, certificado, vault, Artifact Registry, SAs y buckets de Cloud Build.
# Conserva el proyecto, la facturacion y el bucket del estado (vacio de recursos).
# Uso: PROJECT_ID=mi-proyecto scripts/down.sh   (pide escribir el PROJECT_ID para confirmar)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
export PROJECT_ID=${PROJECT_ID:?PROJECT_ID requerido} REGION=${REGION:-us-central1}
export STATE_BUCKET=${STATE_BUCKET:-${PROJECT_ID}-tfstate} APIGEE_ORG=$PROJECT_ID
source scripts/lib/tf.sh
if [[ "${CONFIRM:-}" != "$PROJECT_ID" ]]; then
  read -r -p "Se eliminara TODO lo de la PoC en ${PROJECT_ID} (irreversible). Escribe el PROJECT_ID para confirmar: " ans
  [[ "$ans" == "$PROJECT_ID" ]] || { echo "cancelado"; exit 1; }
fi
TOKEN=$(gcloud auth print-access-token); A="https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}"

echo "==> Retirando proxies desplegados (Apigee no borra ambientes con despliegues)"
for E in $(curl -s -H "Authorization: Bearer $TOKEN" "$A/environments" | jq -r '.[]?'); do
  curl -s -H "Authorization: Bearer $TOKEN" "$A/environments/$E/deployments" | jq -r '.deployments[]? | "\(.apiProxy) \(.revision)"' |
  while read -r api rev; do
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN" "$A/environments/$E/apis/$api/revisions/$rev/deployments" && echo "  undeploy $api r$rev de $E"
  done
done

echo "==> Recursos creados por los pipelines de APIs (target servers y KVM por ambiente)"
for E in $(curl -s -H "Authorization: Bearer $TOKEN" "$A/environments" | jq -r '.[]?'); do
  for ts in $(curl -s -H "Authorization: Bearer $TOKEN" "$A/environments/$E/targetservers" | jq -r '.[]?'); do
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN" "$A/environments/$E/targetservers/$ts" && echo "  target server $ts ($E)"
  done
  for kvm in $(curl -s -H "Authorization: Bearer $TOKEN" "$A/environments/$E/keyvaluemaps" | jq -r '.[]?'); do
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN" "$A/environments/$E/keyvaluemaps/$kvm" && echo "  KVM $kvm ($E)"
  done
done

echo "==> Capa de ambientes"
tf_init terraform/environments && tf terraform/environments destroy -input=false -auto-approve
echo "==> Bootstrap (org e instancia: 20-40 min)"
tf_init terraform/bootstrap && tf terraform/bootstrap destroy -input=false -auto-approve
echo "==> Buckets implicitos de Cloud Build"
PNUM=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
for b in "gs://${PROJECT_ID}_cloudbuild" "gs://${PNUM}-${REGION}-cloudbuild-logs"; do gcloud storage rm -r "$b" --quiet 2>/dev/null && echo "  borrado $b" || true; done
echo "LISTO: plataforma eliminada (se conservan el proyecto y gs://${STATE_BUCKET})"
