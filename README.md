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

## Plataforma desde GitHub Actions (`platform-apply`) y ambientes adicionales

`platform-apply` ejecuta lo mismo que `up.sh`, pero desde un runner. El estado queda en GCS, nunca en el runner.
Cada plataforma es un environment de GitHub `platform-<nombre>`, con su propio proyecto, su propia llave y sus propias variables.

| Plataforma | Proyecto | Ambientes | Uso |
|---|---|---|---|
| `principal` | proyecto de la PoC | `dev qa` | Solo `plan` antes de la sesión: el resultado debe ser "No changes" |
| `aislada` | otro proyecto (mismo billing) | `staging prod` | `up` crea otra org de evaluación con sus ambientes, en `staging.<IP>.nip.io` y `prod.<IP>.nip.io` |

**Por qué otro proyecto:** una org de evaluación admite **2 ambientes** y no se puede convertir a una org paga.
Con más ambientes en la misma org haría falta PAYG. Además, una producción aislada en su propio proyecto y org es la práctica recomendada:
- radio de impacto separado;
- IAM separado;
- llaves separadas.

`up.sh` acepta `ENVIRONMENTS="staging prod"`. Con ese valor genera la lista para el bootstrap y el mapa para la capa de ambientes.
Con el valor por defecto `dev qa`, los valores son idénticos a los actuales.

`setup_github.sh` con `ENV_SCOPED=1` publica en el repo de APIs a nivel de environment (`staging`, `prod`):
- secret `GCP_SA_KEY`;
- variables `APIGEE_ORG`, `APIGEE_NAME`, `APIGEE_HOST` y `BACKEND_HOST`.

No toca el secret ni las variables del repo (org principal). `prod` queda con required reviewers, y solo se despliega desde tags `v*`.

## Notas

- La instancia de **evaluación** admite 2 ambientes adjuntos (dev y qa).
- En repos privados del plan gratuito de GitHub no hay *required reviewers*: el gate de QA lo aplica `promote-qa.yml` en el repo de APIs.
- `terraform/bootstrap/README.md` detalla el bootstrap (PSC, hostnames, KMS para orgs de pago).
