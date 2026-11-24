# bt-claro-apigee-infrastructure

Plataforma **Apigee X** de la PoC CI/CD de **Claro CENAM**, como código. Este repo crea y opera lo **compartido**; las APIs
(proxies, policies, target servers, KVM, productos, apps) viven en su propio repo y se despliegan con su propio pipeline:
**[bt-claro-apigee-services](https://github.com/bt-blautech/bt-claro-apigee-services)**.

## Qué gestiona

| Capa | Ruta | Recursos | Estado (GCS) |
|---|---|---|---|
| Bootstrap | `terraform/bootstrap` | VPC dedicada `<name>-vpc` (subred + rango de peering), organización Apigee X, instancia, LB HTTPS + Private Service Connect, certificado gestionado, vault (Secret Manager), Artifact Registry, SAs `<name>-cicd` / `<name>-mock` | `apigee-bootstrap` |
| Ambientes | `terraform/environments` | Ambientes `dev`/`qa`, environment groups (hostnames), attachments, backends de prueba en Cloud Run, truststores por ambiente (`certs/<env>/*.pem`) + referencias | `apigee-environments` |
| Backend de prueba | `mock/` | Servicio de clientes (`/poc-customers/v0/customers`) protegido con `x-api-secret` | — |

`APIGEE_NAME` (por defecto `poc`) da nombre a toda la plataforma. La organización de Apigee X siempre es el `PROJECT_ID`.

## Separación de responsabilidades

| | bt-claro-apigee-infrastructure (este repo) | bt-claro-apigee-services (APIs) |
|---|---|---|
| Cambia | Rara vez (red, org, ambientes, certificados) | A diario (proxies, policies, configuración por API) |
| Credencial | Usuario administrador o `GCP_TF_SA_KEY` (permisos amplios) | `GCP_SA_KEY` de `<name>-cicd`: solo `apigee.admin` + `apigee.deployer` + lectura del vault |
| Publica hacia el otro repo | `APIGEE_HOST` y `BACKEND_HOST` por ambiente, `APIGEE_ORG`, `APIGEE_NAME`, `QA_APPROVERS`, `GCP_SA_KEY` (`scripts/setup_github.sh`) | — |
| Pipeline | `platform-ci` (validación) · `platform-apply` (manual) | `ci-validate` · `cd-pipeline` · `promote-qa` · `rollback` |

## Uso

```bash
# Plataforma completa desde un proyecto con facturacion (45-75 min la primera vez)
PROJECT_ID=cs-poc-6k18qfubvs1hrrde4cc8tfs APIGEE_NAME=claro-poc scripts/up.sh

# Configurar el repo de APIs (secreto, variables y environments de GitHub)
PROJECT_ID=cs-poc-6k18qfubvs1hrrde4cc8tfs scripts/setup_github.sh bt-blautech/bt-claro-apigee-services

# Validar la plataforma (org, instancia, ambientes adjuntos, TLS de cada hostname)
APIGEE_ORG=cs-poc-6k18qfubvs1hrrde4cc8tfs scripts/check_platform.sh

# Eliminar todo (irreversible; conserva el proyecto y el bucket del estado)
PROJECT_ID=cs-poc-6k18qfubvs1hrrde4cc8tfs scripts/down.sh
```

Variables de `up.sh`: `PROJECT_ID` (obligatoria), `APIGEE_NAME`, `REGION` (`us-central1`), `DOMAIN` (vacío = `<env>.<IP>.nip.io`),
`SUBNET_CIDR` (`10.10.0.0/24`), `PEERING_CIDR` (`10.20.0.0/22`), `BILLING_TYPE` (`EVALUATION`).

Requisitos: `gcloud` (con `gcloud auth login` y `gcloud auth application-default login`), `terraform` ≥ 1.6, `gh`, `jq`, `openssl`.

## Notas

- La instancia de **evaluación** admite 2 ambientes adjuntos (dev y qa).
- En repos privados del plan gratuito de GitHub no hay *required reviewers*: el gate de QA lo aplica `promote-qa.yml` en el repo de APIs.
- `terraform/bootstrap/README.md` detalla el bootstrap (PSC, hostnames, KMS para orgs de pago).
