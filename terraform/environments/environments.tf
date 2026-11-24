# ---------------------------------------------------------------------------
# Capa de AMBIENTES compartidos (plataforma). Lo que es de cada API (target server, KVM,
# producto, apps) vive en el repo de la API y lo aplica su pipeline.
# ---------------------------------------------------------------------------
data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "apigee-bootstrap"
  }
}

locals {
  org_id     = "organizations/${var.project_id}"
  boot       = data.terraform_remote_state.bootstrap.outputs
  mock_image = "${local.boot.artifact_registry}/mock-customers:${var.mock_image_tag}"
}

# --- Apigee: ambiente, environment group (hostname del bootstrap) y attachments ----
resource "google_apigee_environment" "env" {
  for_each     = var.environments
  org_id       = local.org_id
  name         = each.key
  display_name = upper(each.key)
  description  = "Ambiente ${upper(each.key)} de la plataforma ${local.boot.name}"
}

resource "google_apigee_envgroup" "eg" {
  for_each  = var.environments
  org_id    = local.org_id
  name      = each.value.envgroup
  hostnames = [local.boot.hostnames[each.key]]
}

resource "google_apigee_envgroup_attachment" "eg" {
  for_each    = var.environments
  envgroup_id = google_apigee_envgroup.eg[each.key].id
  environment = google_apigee_environment.env[each.key].name
}

resource "google_apigee_instance_attachment" "inst" {
  for_each    = var.environments
  instance_id = "${local.org_id}/instances/${local.boot.instance_name}"
  environment = google_apigee_environment.env[each.key].name
}

# --- Backend de prueba por ambiente (Cloud Run) ------------------------------------
resource "google_cloud_run_v2_service" "mock" {
  for_each            = var.environments
  name                = "${local.boot.name}-${each.value.mock_service}"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  lifecycle {
    ignore_changes = [scaling] # bloque a nivel de servicio que devuelve la API (el escalado real va en template)
  }

  template {
    service_account = local.boot.mock_service_account
    scaling {
      min_instance_count = each.value.mock_min_instances # evita arranque en frio (< 500 ms)
      max_instance_count = 3
    }
    containers {
      image = local.mock_image
      env {
        name  = "ENVIRONMENT"
        value = each.key
      }
      env {
        name = "API_SECRET" # mismo secreto del vault que Apigee inyecta como x-api-secret
        value_source {
          secret_key_ref {
            secret  = local.boot.vault_secrets[each.key]
            version = "latest"
          }
        }
      }
      resources {
        limits   = { cpu = "1", memory = "512Mi" } # minimo con CPU siempre asignada
        cpu_idle = true                            # CPU solo durante peticiones
      }
    }
  }
}

# Invocable sin IAM: la proteccion es el header x-api-secret que solo Apigee conoce
resource "google_cloud_run_v2_service_iam_member" "public" {
  for_each = google_cloud_run_v2_service.mock
  name     = each.value.name
  location = each.value.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Truststore por ambiente + referencia (certificados diferenciados DEV vs QA) ----
# Cada certs/<env>/*.pem (solo CA publicas) es un alias. Las APIs usan ref://ref-<truststore>.
locals {
  ca_certs = merge([for e, c in var.environments : {
    for f in fileset("${path.module}/../../certs/${e}", "*.pem") : "${e}/${trimsuffix(f, ".pem")}" => { env = e, alias = trimsuffix(f, ".pem"), file = "${path.module}/../../certs/${e}/${f}" }
  }]...)
}

resource "google_apigee_env_keystore" "truststore" {
  for_each   = var.environments
  env_id     = google_apigee_environment.env[each.key].id
  name       = each.value.truststore
  depends_on = [google_apigee_instance_attachment.inst]
}

resource "google_apigee_keystores_aliases_key_cert_file" "backend_ca" {
  for_each    = local.ca_certs
  org_id      = var.project_id
  environment = each.value.env
  keystore    = google_apigee_env_keystore.truststore[each.value.env].name
  alias       = each.value.alias
  cert        = file(each.value.file)
}

resource "google_apigee_env_references" "truststore" {
  for_each      = var.environments
  env_id        = google_apigee_environment.env[each.key].id
  name          = "ref-${each.value.truststore}"
  resource_type = "KeyStore"
  refers        = google_apigee_env_keystore.truststore[each.key].name
}
