# terraform/bootstrap — plataforma Apigee X desde cero

Estado: `gs://<PROJECT_ID>-tfstate`, prefix `apigee-bootstrap` (separado de la capa de ambientes).
Normalmente se ejecuta con `scripts/up.sh`; destruye con `scripts/down.sh`.

| Archivo | Gestiona |
|---|---|
| `main.tf` | APIs, rango de peering, Service Networking, **organización Apigee X** (30-60 min) e **instancia** |
| `kms.tf` | Solo `billing_type` PAYG/SUBSCRIPTION: keyring + llaves CMEK para BD del runtime y disco (no probado: la PoC usa EVALUATION) |
| `northbound_lb.tf` | IP global, HTTPS LB `EXTERNAL_MANAGED`, backend **Private Service Connect** (sin VMs puente), certificado gestionado |
| `validation.tf` | `check` por hostname: advierte si el TLS no es válido (certificado aún no emitido o DNS incorrecto) |
| `platform.tf` | Artifact Registry, **vault** (Secret Manager, sin valores), SAs `sa-poc-cicd` y `sa-mock-customers` + IAM |
| `outputs.tf` | `hostnames` (uno por ambiente), instancia, SAs, registro: los consume `terraform/` vía `terraform_remote_state` |

## Hostnames

Sin dominio propio: `<env>.<IP-del-LB>.nip.io` (se calculan de la IP que crea Terraform).
Con dominio: `domain = "api.ejemplo.com"` → `dev.api.ejemplo.com`, `qa.api.ejemplo.com` (crear los registros A hacia `lb_ip`).

## Notas

- La instancia de **evaluación** admite **2 ambientes adjuntos** (dev y qa).
- En producción agregar `lifecycle { prevent_destroy = true }` a la org y la instancia.
- `imports.tf.example`: solo para ADOPTAR una org creada con el asistente de la consola.
