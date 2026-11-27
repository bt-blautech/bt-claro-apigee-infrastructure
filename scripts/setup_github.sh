#!/usr/bin/env bash
# Configura el repositorio de GitHub de las APIs para su pipeline (Cap. 3, 5, 8):
#  - secret GCP_SA_KEY: llave JSON de sa-poc-cicd, enviada directo a GitHub (nunca toca disco)
#  - variables APIGEE_ORG, APIGEE_NAME, QA_APPROVERS; environments dev y qa con APIGEE_HOST y
#    BACKEND_HOST (salidas de terraform/environments: la API crea su target server con ese host)
#  - qa con required reviewers (gate) y despliegue solo desde main o tags v*
#  - permisos de escritura para el GITHUB_TOKEN (comentarios de trazabilidad)
# Uso: PROJECT_ID=mi-proyecto scripts/setup_github.sh <owner/repo> [--rotate-key]
# Org aislada (staging/prod en OTRO proyecto): ENV_SCOPED=1 ENVIRONMENTS="staging prod" PROJECT_ID=otro-proyecto
#   publica TODO a nivel de environment (GCP_SA_KEY, APIGEE_ORG, APIGEE_NAME, APIGEE_HOST, BACKEND_HOST) sin tocar
#   el secreto ni las variables del repo (org principal). Despliegue solo desde tags v*; prod con required reviewers.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
REPO=${1:?uso: setup_github.sh <owner/repo>}
PROJECT_ID=${PROJECT_ID:?PROJECT_ID requerido}
export STATE_BUCKET=${STATE_BUCKET:-${PROJECT_ID}-tfstate}
source scripts/lib/tf.sh
tf_init terraform/bootstrap
SA=$(tf terraform/bootstrap output -raw cicd_service_account)
NAME=$(tf terraform/bootstrap output -raw name)
tf_init terraform/environments
HOSTS=$(tf terraform/environments output -json hostnames)
BACKENDS=$(tf terraform/environments output -json backend_hosts)

if [[ "${ENV_SCOPED:-0}" == "1" ]]; then
  ME=$(gh api user --jq .id)
  KEYJSON=""
  for ENV in ${ENVIRONMENTS:?ENVIRONMENTS requerido con ENV_SCOPED=1}; do
    echo "==> Environment ${ENV} (org ${PROJECT_ID})"
    if [[ "$ENV" == "prod" ]]; then
      body=$(jq -nc --argjson id "$ME" '{reviewers:[{type:"User", id:$id}], deployment_branch_policy:{protected_branches:false, custom_branch_policies:true}}')
    else
      body='{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
    fi
    echo "$body" | gh api -X PUT "repos/${REPO}/environments/${ENV}" --input - >/dev/null
    # Solo releases: el workflow debe lanzarse desde un tag vX.Y.Z
    gh api -X POST "repos/${REPO}/environments/${ENV}/deployment-branch-policies" -f name="v*" -f type="tag" >/dev/null 2>&1 || true
    if gh secret list -R "$REPO" --env "$ENV" | grep -q '^GCP_SA_KEY' && [[ "${2:-}" != "--rotate-key" ]]; then
      echo "  GCP_SA_KEY ya existe (use --rotate-key para crear una nueva)"
    else
      # Una sola llave para los ambientes de esta org; viaja por pipe, nunca a disco
      [[ -n "$KEYJSON" ]] || KEYJSON=$(gcloud iam service-accounts keys create /dev/stdout --iam-account="$SA" --project="$PROJECT_ID" 2>/dev/null | jq -c .)
      printf '%s' "$KEYJSON" | gh secret set GCP_SA_KEY -R "$REPO" --env "$ENV"
      echo "  GCP_SA_KEY creado (llave ${SA})"
    fi
    gh variable set APIGEE_ORG -R "$REPO" --env "$ENV" --body "$PROJECT_ID"
    gh variable set APIGEE_NAME -R "$REPO" --env "$ENV" --body "$NAME"
    gh variable set APIGEE_HOST -R "$REPO" --env "$ENV" --body "$(echo "$HOSTS" | jq -r --arg e "$ENV" '.[$e]')"
    gh variable set BACKEND_HOST -R "$REPO" --env "$ENV" --body "$(echo "$BACKENDS" | jq -r --arg e "$ENV" '.[$e]')"
    echo "  APIGEE_HOST=$(echo "$HOSTS" | jq -r --arg e "$ENV" '.[$e]') · BACKEND_HOST=$(echo "$BACKENDS" | jq -r --arg e "$ENV" '.[$e]')"
  done
  unset KEYJSON
  echo "LISTO (org aislada ${PROJECT_ID}): environments ${ENVIRONMENTS} configurados en ${REPO}"
  exit 0
fi

echo "==> Secret GCP_SA_KEY (llave JSON de ${SA})"
if gh secret list -R "$REPO" | grep -q '^GCP_SA_KEY' && [[ "${2:-}" != "--rotate-key" ]]; then
  echo "  ya existe (use --rotate-key para crear una nueva)"
else
  # jq -c: JSON en UNA linea. GitHub enmascara los secretos multilinea linea por linea, y lineas
  # como "{" o "}" acaban reemplazadas por *** en todos los logs; en una linea se enmascara entero.
  KEYJSON=$(gcloud iam service-accounts keys create /dev/stdout --iam-account="$SA" --project="$PROJECT_ID" 2>/dev/null | jq -c .)
  NEW_ID=$(jq -r .private_key_id <<<"$KEYJSON")
  printf '%s' "$KEYJSON" | gh secret set GCP_SA_KEY -R "$REPO"; unset KEYJSON
  echo "  creado en una linea, llave ${NEW_ID:0:8}... (no se escribio en disco)"
  if [[ "${2:-}" == "--rotate-key" ]]; then  # deja activa solo la llave recien creada
    for k in $(gcloud iam service-accounts keys list --iam-account="$SA" --managed-by=user --format="value(name.basename())"); do
      [[ "$k" != "$NEW_ID" ]] && gcloud iam service-accounts keys delete "$k" --iam-account="$SA" --quiet 2>/dev/null && echo "  llave anterior ${k:0:8}... revocada"
    done
  fi
fi

echo "==> Variables"
gh variable set APIGEE_ORG -R "$REPO" --body "$PROJECT_ID"
gh variable set APIGEE_NAME -R "$REPO" --body "$NAME"
gh variable set QA_APPROVERS -R "$REPO" --body "${QA_APPROVERS:-$(gh api user --jq .login)}"   # gate de promote-qa.yml

ME=$(gh api user --jq .id)
for ENV in dev qa; do
  echo "==> Environment ${ENV}"
  if [[ "$ENV" == "qa" ]]; then
    body=$(jq -nc --argjson id "$ME" '{reviewers:[{type:"User", id:$id}], deployment_branch_policy:{protected_branches:false, custom_branch_policies:true}}')
  else
    body='{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
  fi
  if ! echo "$body" | gh api -X PUT "repos/${REPO}/environments/${ENV}" --input - >/dev/null 2>/dev/null; then
    # Repo privado en plan gratuito: sin required reviewers. El gate lo aplica promote-qa.yml
    # (QA_APPROVERS + confirmacion + run de DEV exitoso + mismo artefacto).
    echo "  required reviewers no disponibles en este plan: environment sin reviewers, gate en promote-qa.yml"
    echo '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
      | gh api -X PUT "repos/${REPO}/environments/${ENV}" --input - >/dev/null
  fi
  for pol in "main:branch" "v*:tag"; do
    gh api -X POST "repos/${REPO}/environments/${ENV}/deployment-branch-policies" -f name="${pol%%:*}" -f type="${pol##*:}" >/dev/null 2>&1 || true
  done
  gh variable set APIGEE_HOST -R "$REPO" --env "$ENV" --body "$(echo "$HOSTS" | jq -r --arg e "$ENV" '.[$e]')"
  gh variable set BACKEND_HOST -R "$REPO" --env "$ENV" --body "$(echo "$BACKENDS" | jq -r --arg e "$ENV" '.[$e]')"
  echo "  BACKEND_HOST=$(echo "$BACKENDS" | jq -r --arg e "$ENV" '.[$e]')"
  echo "  APIGEE_HOST=$(echo "$HOSTS" | jq -r --arg e "$ENV" '.[$e]')$([[ $ENV == qa ]] && echo ' · aprobadores (QA_APPROVERS): '"${QA_APPROVERS:-$(gh api user --jq .login)}")"
done

echo "==> Permisos del GITHUB_TOKEN (lectura/escritura)"
gh api -X PUT "repos/${REPO}/actions/permissions/workflow" -f default_workflow_permissions=write -F can_approve_pull_request_reviews=false >/dev/null && echo "  ok"
echo "LISTO. Verificacion:"; gh secret list -R "$REPO"; gh variable list -R "$REPO"
