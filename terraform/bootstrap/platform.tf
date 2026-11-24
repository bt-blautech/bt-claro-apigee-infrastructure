# ---------------------------------------------------------------------------
# Plataforma compartida de la PoC (se crea una vez):
#  - APIs adicionales, Artifact Registry para la imagen del mock
#  - Secret Manager: contenedores del vault (SIN valores: nunca pasan por el tfstate)
#  - Service accounts: CI/CD (GitHub Actions) y runtime de Cloud Run, con minimo acceso
# ---------------------------------------------------------------------------
resource "google_project_service" "platform" {
  for_each = toset([
    "run.googleapis.com", "artifactregistry.googleapis.com", "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "poc" {
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  description   = "Imagenes de la PoC (backend mock de clientes)"
  depends_on    = [google_project_service.platform]
}

# Vault: un secreto por ambiente (KVM:api_secret = vault:poc-<env>-api-secret)
resource "google_secret_manager_secret" "api_secret" {
  for_each  = toset(var.environments)
  secret_id = "${var.name}-${each.value}-api-secret"
  labels    = { env = each.value, platform = var.name }
  replication {
    auto {}
  }
  depends_on = [google_project_service.platform]
}

# SA de GitHub Actions (requisito de los lineamientos: apigee.admin + apigee.deployer)
resource "google_service_account" "cicd" {
  account_id   = "${var.name}-cicd"
  display_name = "GitHub Actions - ${var.name} CI/CD"
}

resource "google_project_iam_member" "cicd" {
  for_each = toset(var.cicd_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.cicd.email}"
}

# SA de runtime de los mocks en Cloud Run
resource "google_service_account" "mock" {
  account_id   = "${var.name}-mock"
  display_name = "Cloud Run - ${var.name} mocks"
}

# Acceso al vault: solo el pipeline (para cargar el KVM) y el mock (para validar el header)
resource "google_secret_manager_secret_iam_member" "cicd" {
  for_each  = google_secret_manager_secret.api_secret
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_secret_manager_secret_iam_member" "mock" {
  for_each  = google_secret_manager_secret.api_secret
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mock.email}"
}

# El pipeline podra leer la imagen y desplegar revisiones de Cloud Run si se automatiza el mock
resource "google_artifact_registry_repository_iam_member" "cicd_reader" {
  location   = google_artifact_registry_repository.poc.location
  repository = google_artifact_registry_repository.poc.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cicd.email}"
}

# Cloud Build con SA propia: no depende de la SA por defecto de Compute (en organizaciones con
# iam.automaticIamGrantsForDefaultServiceAccounts esa SA no recibe permisos). Bucket propio para el
# codigo fuente subido y los logs del build; la SA solo escribe en el repositorio de imagenes.
resource "google_service_account" "build" {
  account_id   = "${var.name}-build"
  display_name = "Cloud Build - ${var.name} imagenes"
}

resource "google_storage_bucket" "build" {
  name                        = "${var.project_id}-${var.name}-build"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# objectAdmin: subir/leer el codigo y escribir logs; legacyBucketReader: storage.buckets.get, que
# Cloud Build exige para aceptar un bucket de logs propio
resource "google_storage_bucket_iam_member" "build" {
  for_each = toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader"])
  bucket   = google_storage_bucket.build.name
  role     = each.value
  member   = "serviceAccount:${google_service_account.build.email}"
}

resource "google_artifact_registry_repository_iam_member" "build_writer" {
  location   = google_artifact_registry_repository.poc.location
  repository = google_artifact_registry_repository.poc.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.build.email}"
}

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.build.email}"
}

moved {
  from = google_storage_bucket_iam_member.build
  to   = google_storage_bucket_iam_member.build["roles/storage.objectAdmin"]
}
