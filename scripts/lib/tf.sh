#!/usr/bin/env bash
# Helpers de Terraform para los scripts de orquestacion.
# Credenciales: Application Default Credentials (se renuevan solas; necesarias para crear la org,
# que tarda 30-60 min). Si no existen, se cae al token de gcloud (vence en 1 h) con advertencia.
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}

tf_auth() {
  if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    unset GOOGLE_OAUTH_ACCESS_TOKEN
  else
    echo "ADVERTENCIA: sin ADC (gcloud auth application-default login); uso token de 1 h" >&2
    export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)
  fi
}

tf() {  # tf <dir> <args...>
  local dir=$1; shift
  tf_auth
  terraform -chdir="$ROOT/$dir" "$@"
}

tf_init() {  # tf_init <dir>
  tf "$1" init -input=false -reconfigure -backend-config="bucket=${STATE_BUCKET}" >/dev/null
}
