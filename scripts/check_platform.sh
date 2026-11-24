#!/usr/bin/env bash
# Valida que la plataforma esta lista para desplegar. Sale != 0 si algo falla (bloqueo duro).
#  1. Org Apigee ACTIVE  2. Instancia ACTIVE  3. Ambientes adjuntos a la instancia
#  4. Hostname de cada ambiente negocia TLS valido (sin -k) y llega a Apigee
# Uso: check_platform.sh [--wait-cert]   (con --wait-cert espera hasta 60 min al certificado)
set -euo pipefail
cd "$(dirname "$0")/.."
ORG=${APIGEE_ORG:?APIGEE_ORG requerido}
A="https://apigee.googleapis.com/v1/organizations/${ORG}"
TOKEN=${APIGEE_TOKEN:-$(gcloud auth print-access-token)}
get() { curl -s -H "Authorization: Bearer ${TOKEN}" "$A$1"; }
fail=0
ok() { printf '  [OK]   %s\n' "$*"; }
ko() { printf '  [FAIL] %s\n' "$*"; fail=1; }

echo "== Plataforma Apigee (${ORG})"
st=$(get "" | jq -r '.state // .error.status'); [[ "$st" == "ACTIVE" ]] && ok "org ACTIVE ($(get "" | jq -r .billingType))" || ko "org: $st"
inst=$(get /instances | jq -r '.instances[0].name // empty')
ist=$(get /instances | jq -r '.instances[0].state // "NONE"'); [[ "$ist" == "ACTIVE" ]] && ok "instancia ${inst} ACTIVE" || ko "instancia: $ist"
attached=$(get "/instances/${inst}/attachments" | jq -r '[.attachments[]?.environment] | join(",")')
for E in ${ENVIRONMENTS:-dev qa}; do  # ambientes esperados
  [[ ",$attached," == *",$E,"* ]] && ok "ambiente $E adjunto a la instancia" || ko "ambiente $E no adjunto (adjuntos: ${attached:-ninguno})"
done

echo "== Entrada por internet (TLS valido, sin -k)"
HOSTS=${HOSTNAMES:-$(cd terraform/bootstrap && terraform output -json hostnames 2>/dev/null | jq -r 'to_entries[] | .value')}
for H in $HOSTS; do
  tries=1; [[ "${1:-}" == "--wait-cert" ]] && tries=60
  for i in $(seq 1 $tries); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${H}/" || true)
    [[ "$code" != "000" ]] && break
    [[ $tries -gt 1 ]] && { echo "  ... ${H}: certificado aun no emitido, reintento en 60 s ($i/$tries)"; sleep 60; }
  done
  # Apigee responde 404 en la raiz (no hay proxy en "/"); 000 = TLS invalido o sin conexion
  [[ "$code" != "000" ]] && ok "https://${H}/ -> HTTP ${code} (TLS valido)" || ko "https://${H}/ sin TLS valido (certificado PROVISIONING o DNS)"
done

[[ $fail -eq 0 ]] && echo "PLATAFORMA OK" || { echo "PLATAFORMA CON ERRORES" >&2; exit 1; }
