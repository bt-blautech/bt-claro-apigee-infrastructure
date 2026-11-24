#!/usr/bin/env bash
# Carga el valor inicial del vault (Secret Manager) por ambiente, solo si aun no tiene versiones.
# El valor se genera aleatorio y viaja por pipe: nunca se imprime, ni se guarda en disco, Git o tfstate.
# Rotacion: ejecutar con ROTATE=1 (agrega una nueva version) y luego scripts/apply_config.sh <env>.
set -euo pipefail
PROJECT=${PROJECT_ID:?PROJECT_ID requerido}
NAME=${APIGEE_NAME:?APIGEE_NAME requerido}
for ENV in ${ENVIRONMENTS:-dev qa}; do
  S="${NAME}-${ENV}-api-secret"
  n=$(gcloud secrets versions list "$S" --project "$PROJECT" --filter="state:ENABLED" --format="value(name)" | wc -l | tr -d ' ')
  if [[ "$n" -gt 0 && "${ROTATE:-0}" != "1" ]]; then
    echo "$S: ya tiene $n version(es) habilitada(s); sin cambios"
    continue
  fi
  openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add "$S" --project "$PROJECT" --data-file=- >/dev/null
  echo "$S: nueva version cargada (valor no mostrado)"
done
